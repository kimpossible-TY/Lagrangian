// Terminal transport only: Chromium owns document layout, selection and actions.
import { StringDecoder } from "node:string_decoder";

const ESC = "\x1b";

// One owner for the terminal synchronized-update policy shared by native and
// editor transports. Unknown terminals ignore DECSET 2026.
export const synchronizedStart = `${ESC}[?2026h`;
export const synchronizedFinish = `${ESC}[?2026l`;

export function synchronizedOutput(sequence) {
  return `${synchronizedStart}${sequence}${synchronizedFinish}`;
}

export function graphicsProtocol(environment = process.env) {
  if (environment.WT_SESSION || environment.TERM_PROGRAM === "Windows_Terminal") return "sixel";
  // Current iTerm2 supports Kitty graphics without OSC file-display prompts.
  if (environment.TERM_PROGRAM === "iTerm.app") return "kitty";
  if (
    environment.KITTY_WINDOW_ID ||
    environment.TERM === "xterm-kitty" ||
    ["WezTerm", "ghostty"].includes(environment.TERM_PROGRAM)
  )
    return "kitty";
  return null;
}

export function terminalSize(columns, rows, cellWidth = 9, cellHeight = 18) {
  const width = Math.max(1, Math.trunc(columns || 80));
  const lines = Math.max(2, Math.trunc(rows || 24));
  return {
    columns: width,
    rows: lines,
    imageRows: lines - 1,
    width: Math.max(1, Math.round(width * cellWidth)),
    height: Math.max(1, Math.round((lines - 1) * cellHeight)),
    cellWidth,
    cellHeight,
  };
}

export function mousePosition(event, size) {
  if (
    event.column < 1 ||
    event.row < 1 ||
    event.column > size.columns ||
    event.row > size.imageRows
  )
    return null;
  return {
    x: Math.min(size.width - 1, ((event.column - 0.5) * size.width) / size.columns),
    y: Math.min(size.height - 1, ((event.row - 0.5) * size.height) / size.imageRows),
  };
}

export function pngSequence(png, size, protocol) {
  const encoded = Buffer.from(png).toString("base64");
  if (protocol === "iterm2") {
    return `${ESC}[H${ESC}]1337;File=inline=1;size=${png.length};width=${size.columns};height=${size.imageRows};preserveAspectRatio=0:${encoded}\x07`;
  }
  if (protocol !== "kitty") throw new Error(`Unsupported terminal image protocol: ${protocol}`);
  const chunks = [];
  for (let offset = 0; offset < encoded.length; offset += 4096) {
    const first = offset === 0;
    const more = offset + 4096 < encoded.length ? 1 : 0;
    const metadata = first
      ? `a=T,f=100,i=39731,p=1,q=2,C=1,c=${size.columns},r=${size.imageRows},`
      : "";
    chunks.push(`${ESC}_G${metadata}m=${more};${encoded.slice(offset, offset + 4096)}${ESC}\\`);
  }
  return `${ESC}[H${chunks.join("")}`;
}

export const terminalStart = `${ESC}[?1049h${ESC}[?25l${ESC}[?1002h${ESC}[?1006h${ESC}[?2004h${ESC}[2J`;
export const terminalFinish = `${ESC}_Ga=d,d=I,i=39731,q=2;${ESC}\\${ESC}[?2004l${ESC}[?1006l${ESC}[?1002l${ESC}[?7h${ESC}[?25h${ESC}[?1049l`;
export const queryCellSize = `${ESC}[16t${ESC}]1337;ReportCellSize\x07${ESC}[14t`;

export function statusSequence(message, size) {
  // Never permit document titles, errors or paths to inject terminal controls.
  const text = String(message).replace(/[\x00-\x1f\x7f-\x9f]/g, " ");
  return `${ESC}[${size.rows};1H${ESC}[2K${ESC}[?7l${text.slice(0, Math.max(0, size.columns - 1))}${ESC}[?7h`;
}

/** Incremental decoder: terminal reports often arrive split across reads. */
export class TerminalInput {
  constructor() {
    this.decoder = new StringDecoder("utf8");
    this.pending = "";
  }

  read(bytes) {
    this.pending += this.decoder.write(Buffer.from(bytes));
    const events = [];
    while (this.pending) {
      if (this.pending[0] !== ESC) {
        const character = String.fromCodePoint(this.pending.codePointAt(0));
        this.pending = this.pending.slice(character.length);
        events.push({ type: "key", value: character });
        continue;
      }
      if (this.pending.startsWith(`${ESC}[200~`)) {
        const end = this.pending.indexOf(`${ESC}[201~`, 6);
        if (end < 0) break;
        events.push({ type: "paste", value: this.pending.slice(6, end) });
        this.pending = this.pending.slice(end + 6);
        continue;
      }
      if (this.pending.startsWith(`${ESC}]`)) {
        const osc = this.pending.match(/^\x1b\]([^\x07]*?)(?:\x07|\x1b\\)/);
        if (!osc) break;
        this.pending = this.pending.slice(osc[0].length);
        const cell = osc[1].match(
          /^1337;ReportCellSize=(\d+(?:\.\d+)?);(\d+(?:\.\d+)?)(?:;(\d+(?:\.\d+)?))?$/,
        );
        if (cell)
          events.push({
            type: "geometry",
            kind: "iterm",
            height: Number(cell[1]),
            width: Number(cell[2]),
            scale: Number(cell[3] || 1),
          });
        continue;
      }
      if (this.pending.startsWith(`${ESC}_`) || this.pending.startsWith(`${ESC}P`)) {
        // Graphics acknowledgements and device-control reports are terminal
        // messages, never keyboard input. Keep fragmented strings until ST so
        // their payload cannot invoke q/h/s/u/g or other Reader shortcuts.
        const end = this.pending.indexOf(`${ESC}\\`, 2);
        if (end < 0) break;
        this.pending = this.pending.slice(end + 2);
        continue;
      }
      const mouse = this.pending.match(/^\x1b\[<(\d+);(\d+);(\d+)([Mm])/);
      if (mouse) {
        this.pending = this.pending.slice(mouse[0].length);
        events.push({
          type: "mouse",
          button: Number(mouse[1]),
          column: Number(mouse[2]),
          row: Number(mouse[3]),
          released: mouse[4] === "m",
        });
        continue;
      }
      const geometry = this.pending.match(/^\x1b\[(4|6);(\d+);(\d+)t/);
      if (geometry) {
        this.pending = this.pending.slice(geometry[0].length);
        events.push({
          type: "geometry",
          kind: Number(geometry[1]),
          height: Number(geometry[2]),
          width: Number(geometry[3]),
        });
        continue;
      }
      const csi = this.pending.match(/^\x1b\[[0-9;?]*[A-Za-z~]/);
      if (csi) {
        this.pending = this.pending.slice(csi[0].length);
        events.push({ type: "key", value: csi[0] });
        continue;
      }
      if (this.pending === ESC || /^\x1b\[[0-9;<?]*$/.test(this.pending)) break;
      // Consume an unknown Alt/Meta key with its escape prefix so it cannot
      // become an unmodified Reader shortcut (for example Alt+q must not quit).
      const prefix = this.pending.startsWith(`${ESC}[`) ? 2 : 1;
      const character = String.fromCodePoint(this.pending.codePointAt(prefix));
      this.pending = this.pending.slice(prefix + character.length);
    }
    return events;
  }

  flushEscape() {
    if (this.pending !== ESC) return [];
    this.pending = "";
    return [{ type: "key", value: ESC }];
  }
}

export function browserKey(value) {
  return (
    {
      "\x1b[A": "ArrowUp",
      "\x1b[B": "ArrowDown",
      "\x1b[C": "ArrowRight",
      "\x1b[D": "ArrowLeft",
      "\x1b[5~": "PageUp",
      "\x1b[6~": "PageDown",
      "\x1b[H": "Home",
      "\x1b[F": "End",
      "\x1b[1~": "Home",
      "\x1b[4~": "End",
      "\x1b[3~": "Delete",
      "\x1b[Z": "Shift+Tab",
      "\r": "Enter",
      "\n": "Enter",
      "\t": "Tab",
      "\x7f": "Backspace",
      "\x08": "Backspace",
      "\x1b": "Escape",
    }[value] ?? null
  );
}
