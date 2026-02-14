// Scriptable widget for Copilot Sessions
// Install Scriptable from the Mac App Store, create a new script, paste this in.
// Then add a Scriptable widget to your desktop and select this script.

const WIDGET_DATA = FileManager.local().joinPath(
  FileManager.local().libraryDirectory(),
  "Application Support/CopilotSessions/widget-data.json"
);

async function createWidget() {
  let data;
  try {
    const raw = FileManager.local().readString(WIDGET_DATA);
    data = JSON.parse(raw);
  } catch {
    const w = new ListWidget();
    w.addText("🤖 No data").font = Font.caption1();
    w.addText("Start CopilotSessions.app");
    return w;
  }

  const widget = new ListWidget();
  widget.setPadding(12, 12, 12, 12);

  // Header
  const counts = data.counts;
  const header = widget.addStack();
  const title = header.addText("🤖 Copilot Sessions");
  title.font = Font.boldSystemFont(13);
  header.addSpacer();
  const badge = header.addText(`${counts.working + counts.waiting} active`);
  badge.font = Font.caption1();
  badge.textColor = Color.gray();

  widget.addSpacer(4);

  // Sessions
  const sessions = data.sessions || [];
  const maxShow = config.widgetFamily === "medium" ? 6 : 3;

  for (const s of sessions.slice(0, maxShow)) {
    const row = widget.addStack();
    row.centerAlignContent();
    row.spacing = 4;

    const emoji = row.addText(s.statusEmoji);
    emoji.font = Font.caption1();

    const topic = row.addText(s.topic);
    topic.font = Font.systemFont(12);
    topic.lineLimit = 1;

    row.addSpacer();

    if (s.age) {
      const age = row.addText(s.age);
      age.font = Font.caption2();
      age.textColor = Color.gray();
    }
  }

  if (sessions.length === 0) {
    const empty = widget.addText("No sessions");
    empty.font = Font.caption1();
    empty.textColor = Color.gray();
  }

  widget.addSpacer();

  // Footer
  const footer = widget.addStack();
  const updated = footer.addText(`Updated ${data.updatedAt?.slice(11, 16) || "?"}`);
  updated.font = Font.caption2();
  updated.textColor = Color.gray();

  return widget;
}

const widget = await createWidget();
if (config.runsInWidget) {
  Script.setWidget(widget);
} else {
  widget.presentMedium();
}
Script.complete();
