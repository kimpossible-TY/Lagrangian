//! Mock workspace events and assertions shared by compiler regressions.

use super::*;

pub(super) struct ProjectCompilerHarness {
    pub(super) workspace: MockWorkspace,
    pub(super) compiler: MockProjectCompiler<()>,
    pub(super) notify_rx: mpsc::UnboundedReceiver<NotifyMessage>,
}

impl ProjectCompilerHarness {
    pub(super) fn new(files: &[(&str, &str)]) -> Self {
        Self::with_opts(
            files,
            CompileServerOpts::<MockCompilerFeat, ()> {
                syntax_only: false,
                ..Default::default()
            },
        )
    }

    pub(super) fn ignoring_first_sync(files: &[(&str, &str)]) -> Self {
        Self::with_opts(
            files,
            CompileServerOpts::<MockCompilerFeat, ()> {
                ignore_first_sync: true,
                syntax_only: false,
                ..Default::default()
            },
        )
    }

    pub(super) fn with_opts(
        files: &[(&str, &str)],
        opts: CompileServerOpts<MockCompilerFeat, ()>,
    ) -> Self {
        let mut builder = MockWorkspace::default_builder();
        for (path, source) in files {
            builder = builder.file(path, source.to_string());
        }

        let workspace = builder.build();
        let (compiler, notify_rx) = workspace
            .world(MAIN)
            .project_compiler_with_opts::<()>(opts)
            .unwrap();

        Self {
            workspace,
            compiler,
            notify_rx,
        }
    }

    pub(super) fn compile_primary(&mut self) -> CompiledArtifact<MockCompilerFeat> {
        self.compiler
            .process(Interrupt::Compile(ProjectInsId::PRIMARY));
        self.compile_pending()
    }

    pub(super) fn compile_pending(&mut self) -> CompiledArtifact<MockCompilerFeat> {
        assert!(
            self.compiler.primary.reason.any(),
            "expected a pending compile reason"
        );

        let handler = self.compiler.handler.clone();
        let compile = self
            .compiler
            .primary
            .may_compile(&handler)
            .expect("expected the primary project to compile");
        let artifact = compile();
        self.compiler.process(Interrupt::Compiled(artifact.clone()));
        artifact
    }

    pub(super) fn apply_update(&mut self, change: &MockChange, is_sync: bool) {
        change.apply_as_fs_to_project(&mut self.compiler, is_sync);
    }

    pub(super) fn apply_upstream_update(
        &mut self,
        changeset: FileChangeSet,
        upstream_event: Option<UpstreamUpdateEvent>,
    ) {
        self.compiler
            .process(Interrupt::Fs(FilesystemEvent::UpstreamUpdate {
                changeset,
                upstream_event,
            }));
    }

    pub(super) fn take_upstream_update(&mut self) -> UpstreamUpdateEvent {
        loop {
            let message = self
                .notify_rx
                .try_recv()
                .expect("expected an upstream update notification");
            match message {
                NotifyMessage::UpstreamUpdate(event) => return event,
                NotifyMessage::SyncDependency(..) | NotifyMessage::Settle => {}
            }
        }
    }

    pub(super) fn latest_sync_dependencies(&mut self) -> Vec<PathBuf> {
        self.optional_sync_dependencies()
            .expect("expected SyncDependency notification")
    }

    pub(super) fn optional_sync_dependencies(&mut self) -> Option<Vec<PathBuf>> {
        let mut latest = None;
        while let Ok(message) = self.notify_rx.try_recv() {
            if let NotifyMessage::SyncDependency(deps) = message {
                let mut paths = Vec::new();
                deps.dependencies(&mut |path| paths.push(path.as_ref().to_path_buf()));
                latest = Some(paths);
            }
        }

        latest
    }

    pub(super) fn dependency_paths_after_compile(&mut self) -> Vec<PathBuf> {
        self.latest_sync_dependencies()
    }

    pub(super) fn dependency_paths_after_harmless_compile(
        &mut self,
        previous: &[PathBuf],
    ) -> Vec<PathBuf> {
        self.optional_sync_dependencies()
            .unwrap_or_else(|| previous.to_vec())
    }
}

pub(super) fn default_files() -> Vec<(&'static str, &'static str)> {
    vec![
        (MAIN, "#import \"dep.typ\": value\n#value"),
        (DEP, "#let value = [before]"),
        (UNRELATED, "#let note = [unchanged]"),
    ]
}

pub(super) fn source_snapshot(source: &str) -> FileSnapshot {
    FileResult::Ok(Bytes::from_string(source.to_owned())).into()
}

pub(super) fn read_error_snapshot(path: PathBuf) -> FileSnapshot {
    FileResult::Err(FileError::NotFound(path)).into()
}

pub(super) fn insert_source_change(
    workspace: &MockWorkspace,
    path: &str,
    source: &str,
) -> MockChange {
    MockChange::new(FileChangeSet::new_inserts(vec![(
        workspace.immut_path(path),
        source_snapshot(source),
    )]))
}

pub(super) fn read_error_change(workspace: &MockWorkspace, path: &str) -> MockChange {
    MockChange::new(FileChangeSet::new_inserts(vec![(
        workspace.immut_path(path),
        read_error_snapshot(workspace.path(path)),
    )]))
}

pub(super) fn remove_change(workspace: &MockWorkspace, path: &str) -> MockChange {
    MockChange::new(FileChangeSet::new_removes(vec![workspace.immut_path(path)]))
}

pub(super) fn empty_change() -> MockChange {
    MockChange::new(FileChangeSet::default())
}

pub(super) fn combine_changes(changes: &[MockChange]) -> MockChange {
    let mut changeset = FileChangeSet::default();
    for change in changes {
        changeset.removes.extend(change.changeset().removes.clone());
        changeset.inserts.extend(change.changeset().inserts.clone());
    }

    MockChange::new(changeset)
}

pub(super) fn source_text(
    artifact: &CompiledArtifact<MockCompilerFeat>,
    workspace: &MockWorkspace,
    path: &str,
) -> String {
    artifact
        .graph
        .snap
        .world
        .source_by_path(&workspace.path(path))
        .unwrap()
        .text()
        .to_owned()
}

pub(super) fn source_is_unavailable(
    artifact: &CompiledArtifact<MockCompilerFeat>,
    workspace: &MockWorkspace,
    path: &str,
) -> bool {
    artifact
        .graph
        .snap
        .world
        .source_by_path(&workspace.path(path))
        .is_err()
}

pub(super) fn assert_fs_reason(compiler: &MockProjectCompiler<()>) {
    assert!(
        compiler.primary.reason.by_fs_events,
        "expected filesystem compile reason"
    );
}

pub(super) fn assert_mem_reason(compiler: &MockProjectCompiler<()>) {
    assert!(
        compiler.primary.reason.by_mem_events,
        "expected memory compile reason"
    );
}

pub(super) fn assert_deps_contain(workspace: &MockWorkspace, deps: &[PathBuf], path: &str) {
    assert!(
        deps.contains(&workspace.path(path)),
        "expected dependencies to contain {path:?}; got {deps:?}"
    );
}

pub(super) fn assert_deps_do_not_contain(workspace: &MockWorkspace, deps: &[PathBuf], path: &str) {
    assert!(
        !deps.contains(&workspace.path(path)),
        "expected dependencies not to contain {path:?}; got {deps:?}"
    );
}
pub(super) fn clean_default_harness_with_deps() -> (ProjectCompilerHarness, Vec<PathBuf>) {
    let files = default_files();
    let mut harness = ProjectCompilerHarness::new(&files);
    let initial = harness.compile_primary();
    assert_eq!(initial.error_cnt(), 0);
    let deps = harness.latest_sync_dependencies();
    (harness, deps)
}

pub(super) fn clean_default_harness() -> ProjectCompilerHarness {
    clean_default_harness_with_deps().0
}
