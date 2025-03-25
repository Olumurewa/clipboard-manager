```markdown
# Advanced Clipboard Manager


A feature-rich clipboard manager with custom key bindings, system tray integration, and history management. Works on Linux with X11.

## Features

- 📋 **Clipboard History**: Stores multiple items (text and images)
- ⌨ **Custom Key Bindings**: Configure your own shortcuts
- 🌐 **Global Hotkeys**: Access quickly from anywhere
- 🖼 **Image Support**: Copy and paste images
- 🚀 **Quick Paste**: Instant paste of last copied item
- 🧹 **History Management**: Clear history when needed
- 📂 **Persistent Storage**: Remembers history between sessions
- 🛠 **System Tray Integration**: Always available but out of the way

## Installation

### Requirements
- Python 3.6+
- Linux with X11
- PyQt5
- xclip, xdotool

### Quick Install
```bash
curl -O https://raw.githubusercontent.com/olumurewa/clipboard-manager/main/install_script.sh
chmod +x install_script.sh
./install_script.sh
```

### Manual Installation
1. Clone the repository:
   ```bash
   git clone https://github.com/olumurewa/clipboard-manager.git
   cd clipboard-manager
   ```

2. Install dependencies:
   ```bash
   sudo apt-get install python3 python3-pip python3-pyqt5 xclip xdotool
   pip3 install pyperclip pynput
   ```

3. Run the application:
   ```bash
   python3 clipboard_manager.py
   ```

## Usage

### Basic Controls
- Double-click items to paste them
- Use the system tray icon for quick access
- Configure key bindings from the settings dialog

### Default Key Bindings
| Action            | Default Shortcut |
|-------------------|------------------|
| Show/Hide Window  | Ctrl+Alt+V       |
| Paste Last Item   | Ctrl+Shift+V     |
| Clear History     | Ctrl+Alt+C       |

### Customizing Key Bindings
1. Click "Configure Key Bindings" in the main window
2. Enter your preferred shortcuts
3. Click "Save"
4. Restart the application to apply changes

## Configuration

Configuration files are stored in your home directory:
- `~/.clipboard_manager_config.json` - Clipboard history and settings
- `~/.clipboard_manager_keybindings.json` - Custom key bindings

## Troubleshooting

**Issue**: Hotkeys not working  
**Solution**: Ensure you have `pynput` installed and proper permissions

**Issue**: Can't paste images  
**Solution**: Verify `xclip` is installed and you're using X11

**Issue**: "Failed to connect to bus" error  
**Solution**: Run in a graphical session or enable X11 forwarding for SSH

## Contributing

Contributions are welcome! Please open an issue or pull request for any:
- Bug fixes
- New features
- Documentation improvements

## License

MIT License - See [LICENSE](LICENSE) for details

---

**Tip**: Add the application to your startup applications to always have it available!
```

### Key Sections Included:

1. **Visual Header** - With placeholder for screenshot
2. **Features** - Bullet points highlighting key functionality
3. **Installation** - Both quick and manual methods
4. **Usage** - How to interact with the application
5. **Key Bindings** - Table of default shortcuts
6. **Configuration** - Where settings are stored
7. **Troubleshooting** - Common issues and solutions
8. **Contributing** - How others can help improve
9. **License** - Basic licensing info
