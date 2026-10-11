//! Small editor messages share the reader's HTTP port, independently of rendering.

use std::{collections::HashMap, sync::Arc};

use futures::{SinkExt, StreamExt};
use hyper_tungstenite::{tungstenite::Message, HyperWebsocket};
use parking_lot::Mutex;
use tokio::sync::{mpsc, watch};

type Sender = mpsc::Sender<Message>;

#[derive(Default)]
pub(super) struct EditorRelay {
    sessions: Mutex<HashMap<String, Arc<Session>>>,
}

struct Session {
    host: Sender,
    viewers: Mutex<HashMap<u64, Sender>>,
    closed: watch::Sender<bool>,
}

pub(super) enum EditorRoute<'a> {
    Host(&'a str),
    Viewer(&'a str),
}

pub(super) fn route(path: &str) -> Option<EditorRoute<'_>> {
    let (host, channel) = if let Some(channel) = path.strip_prefix("/_editor/") {
        (true, channel)
    } else {
        (false, path.strip_prefix("/editor/")?)
    };
    if channel.len() != 36
        || !channel.bytes().enumerate().all(|(i, c)| {
            if matches!(i, 8 | 13 | 18 | 23) {
                c == b'-'
            } else {
                c.is_ascii_hexdigit() && !c.is_ascii_uppercase()
            }
        })
    {
        return None;
    }
    Some(if host {
        EditorRoute::Host(channel)
    } else {
        EditorRoute::Viewer(channel)
    })
}

impl EditorRelay {
    /// Reserve a host session before issuing its browser URL. Hosts cannot replace
    /// a live session, and browser requests cannot register hosts.
    pub(super) fn attach(
        self: &Arc<Self>,
        route: EditorRoute<'_>,
        websocket: HyperWebsocket,
    ) -> bool {
        let (tx, rx) = mpsc::channel(16);
        match route {
            EditorRoute::Host(channel) => {
                let mut sessions = self.sessions.lock();
                if sessions.len() >= 32 || sessions.contains_key(channel) {
                    return false;
                }
                let session = Arc::new(Session {
                    host: tx,
                    viewers: Mutex::new(HashMap::new()),
                    closed: watch::channel(false).0,
                });
                sessions.insert(channel.to_owned(), session.clone());
                let relay = self.clone();
                let channel = channel.to_owned();
                tokio::spawn(async move {
                    relay.host(channel, session, websocket, rx).await;
                });
            }
            EditorRoute::Viewer(channel) => {
                let Some(session) = self.sessions.lock().get(channel).cloned() else {
                    return false;
                };
                let mut viewers = session.viewers.lock();
                if viewers.len() >= 16 {
                    return false;
                }
                let id = (0..).find(|id| !viewers.contains_key(id)).unwrap();
                viewers.insert(id, tx);
                drop(viewers);
                tokio::spawn(async move {
                    Self::viewer(id, session, websocket, rx).await;
                });
            }
        }
        true
    }

    async fn host(
        self: Arc<Self>,
        channel: String,
        session: Arc<Session>,
        websocket: HyperWebsocket,
        mut rx: mpsc::Receiver<Message>,
    ) {
        if let Ok(mut socket) = websocket.await {
            if socket
                .send(Message::Binary(
                    b"{\"event\":\"editorReady\"}".as_slice().into(),
                ))
                .await
                .is_ok()
            {
                log::info!("Shared preview editor host connected");
                loop {
                    tokio::select! {
                        Some(message) = rx.recv() => {
                            if socket.send(message).await.is_err() { break; }
                        }
                        message = socket.next() => {
                            match message {
                                Some(Ok(Message::Text(text))) if valid_control(&text, true) => {
                                    let message = Message::Binary(text.as_bytes().to_vec().into());
                                    for viewer in session.viewers.lock().values() {
                                        let _ = viewer.try_send(message.clone());
                                    }
                                }
                                Some(Ok(Message::Ping(bytes))) => {
                                    if socket.send(Message::Pong(bytes)).await.is_err() { break; }
                                }
                                Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                                _ => {}
                            }
                        }
                    }
                }
            }
        }
        session.closed.send_replace(true);
        log::info!("Shared preview editor host disconnected");
        let mut sessions = self.sessions.lock();
        if sessions
            .get(&channel)
            .is_some_and(|s| Arc::ptr_eq(s, &session))
        {
            sessions.remove(&channel);
        }
    }

    async fn viewer(
        id: u64,
        session: Arc<Session>,
        websocket: HyperWebsocket,
        mut rx: mpsc::Receiver<Message>,
    ) {
        let mut closed = session.closed.subscribe();
        if let Ok(mut socket) = websocket.await {
            log::info!("Shared preview editor reader connected");
            notify_viewers(&session);
            while !*closed.borrow() {
                tokio::select! {
                    _ = closed.changed() => break,
                    Some(message) = rx.recv() => {
                        if socket.send(message).await.is_err() { break; }
                    }
                    message = socket.next() => {
                        match message {
                            Some(Ok(Message::Text(text))) if valid_control(&text, false) => {
                                let _ = session.host.try_send(Message::Binary(text.as_bytes().to_vec().into()));
                            }
                            Some(Ok(Message::Ping(bytes))) => {
                                if socket.send(Message::Pong(bytes)).await.is_err() { break; }
                            }
                            Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                            _ => {}
                        }
                    }
                }
            }
            let _ = socket.close(None).await;
        }
        session.viewers.lock().remove(&id);
        log::info!("Shared preview editor reader disconnected");
        notify_viewers(&session);
    }
}

fn notify_viewers(session: &Session) {
    let connected = !session.viewers.lock().is_empty();
    let text = format!("{{\"event\":\"editorConnected\",\"connected\":{connected}}}");
    let _ = session
        .host
        .try_send(Message::Binary(text.into_bytes().into()));
}

fn valid_control(text: &str, from_host: bool) -> bool {
    if text.len() > 8192 {
        return false;
    }
    if from_host {
        matches!(
            serde_json::from_str::<tinymist_preview::ControlPlaneMessage>(text),
            Ok(tinymist_preview::ControlPlaneMessage::ResolveSourceLoc(_))
        )
    } else {
        let Ok(value) = serde_json::from_str::<serde_json::Value>(text) else {
            return false;
        };
        value["event"] == "editorScrollTo"
            && value["filepath"].is_string()
            && ["start", "end"].iter().all(|key| {
                value[key].as_array().is_some_and(|p| {
                    p.len() == 2
                        && p.iter()
                            .all(|v| v.as_u64().is_some_and(|v| v <= u32::MAX.into()))
                })
            })
    }
}
