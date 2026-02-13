.PHONY: build install clean cli menubar all

all: cli menubar

cli:
	ln -sf $(PWD)/src/copilot-sessions ~/.local/bin/copilot-sessions

menubar:
	cd CopilotSessions && swift build -c release

install: cli menubar
	@echo "CLI installed to ~/.local/bin/copilot-sessions"
	@echo "Menu bar app built at CopilotSessions/.build/release/CopilotSessions"
	@echo ""
	@echo "To run the menu bar app:"
	@echo "  ./CopilotSessions/.build/release/CopilotSessions"
	@echo ""
	@echo "To run at login, add to System Settings > General > Login Items"

clean:
	cd CopilotSessions && swift package clean

run-menubar: menubar
	./CopilotSessions/.build/release/CopilotSessions &
