.PHONY: build install clean cli menubar all

all: cli menubar

cli:
	ln -sf $(PWD)/src/copilot-sessions ~/.local/bin/copilot-sessions

menubar:
	cd CopilotSessions && swift build -c release
	cp CopilotSessions/.build/release/CopilotSessions CopilotSessions.app/Contents/MacOS/CopilotSessions
	codesign --force --sign - --identifier com.schlubbi.copilot-sessions --entitlements CopilotSessions.entitlements CopilotSessions.app

install: cli menubar
	@echo "CLI installed to ~/.local/bin/copilot-sessions"
	@echo "Menu bar app: CopilotSessions.app"
	@echo ""
	@echo "To run:  open CopilotSessions.app"
	@echo "To run at login: add CopilotSessions.app to System Settings > General > Login Items"

clean:
	cd CopilotSessions && swift package clean

run-menubar: menubar
	open CopilotSessions.app
