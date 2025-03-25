#!/usr/bin/env python3

import sys
import os
import json
import base64
import hashlib
from PyQt5.QtWidgets import (QApplication, QMainWindow, QVBoxLayout, QHBoxLayout, 
                             QListWidget, QListWidgetItem, QPushButton, QLabel, 
                             QSystemTrayIcon, QMenu, QAction, QDialog, QLineEdit,
                             QMessageBox, QWidget)
from PyQt5.QtGui import QIcon, QPixmap, QImage
from PyQt5.QtCore import Qt, QTimer, QMimeData
import pyperclip

class ClipboardItem:
    def __init__(self, content, content_type):
        self.id = hashlib.md5(str(content).encode()).hexdigest()
        self.content = content
        self.type = content_type
        self.timestamp = os.path.getmtime(os.path.realpath(__file__))

    def to_dict(self):
        if self.type == 'image':
            return {
                'id': self.id,
                'content': base64.b64encode(self.content).decode(),
                'type': self.type,
                'timestamp': self.timestamp
            }
        return {
            'id': self.id,
            'content': self.content,
            'type': self.type,
            'timestamp': self.timestamp
        }

    @classmethod
    def from_dict(cls, data):
        item = cls(data['content'], data['type'])
        item.id = data['id']
        item.timestamp = data.get('timestamp', item.timestamp)
        if item.type == 'image':
            item.content = base64.b64decode(data['content'])
        return item

class ClipboardManager(QMainWindow):
    def __init__(self, max_items=10):
        super().__init__()
        self.max_items = max_items
        self.clipboard = QApplication.clipboard()
        self.history = []
        self.config_path = os.path.expanduser('~/.clipboard_manager_config.json')
        self.keybindings_path = os.path.expanduser('~/.clipboard_manager_keybindings.json')
        
        self.default_keybindings = {
            "activate": "Ctrl+Alt+V",
            "paste_last": "Ctrl+Shift+V",
            "clear_history": "Ctrl+Alt+C"
        }
        self.keybindings = {}
        self.listener = None
        
        self.load_config()
        self.load_keybindings()
        self.init_ui()
        self.setup_system_tray()
        self.setup_global_hotkeys()
        self.start_monitoring()

    def load_keybindings(self):
        try:
            with open(self.keybindings_path, 'r') as f:
                self.keybindings = json.load(f)
        except (FileNotFoundError, json.JSONDecodeError):
            self.keybindings = self.default_keybindings
            self.save_keybindings()

    def save_keybindings(self):
        with open(self.keybindings_path, 'w') as f:
            json.dump(self.keybindings, f, indent=2)

    def setup_global_hotkeys(self):
        try:
            from pynput import keyboard
            
            if self.listener:
                self.listener.stop()
                
            self.listener = keyboard.GlobalHotKeys({
                self.keybindings["activate"]: self.toggle_window,
                self.keybindings["paste_last"]: self.paste_last_item,
                self.keybindings["clear_history"]: self.clear_history
            })
            self.listener.start()
        except ImportError:
            print("pynput not installed - global hotkeys disabled")
        except Exception as e:
            print(f"Failed to setup hotkeys: {e}")

    def toggle_window(self):
        if self.isVisible():
            self.hide()
        else:
            self.show()
            self.activateWindow()
            self.raise_()

    def paste_last_item(self):
        if self.history:
            last_item = self.history[0]
            if last_item.type == 'text':
                self.clipboard.setText(last_item.content)
                if sys.platform == 'linux':
                    os.system('xdotool key ctrl+v')
            elif last_item.type == 'image':
                qimage = QImage.fromData(last_item.content)
                mime_data = QMimeData()
                mime_data.setImageData(qimage)
                self.clipboard.setMimeData(mime_data)

    def init_ui(self):
        self.setWindowTitle('Advanced Clipboard Manager')
        self.setGeometry(100, 100, 600, 400)

        main_layout = QVBoxLayout()
        
        self.clip_list = QListWidget()
        self.clip_list.itemDoubleClicked.connect(self.restore_item)
        main_layout.addWidget(self.clip_list)

        button_layout = QHBoxLayout()
        clear_btn = QPushButton('Clear History')
        clear_btn.clicked.connect(self.clear_history)
        button_layout.addWidget(clear_btn)

        keybindings_btn = QPushButton('Configure Key Bindings')
        keybindings_btn.clicked.connect(self.show_keybindings_dialog)
        button_layout.addWidget(keybindings_btn)

        max_items_label = QLabel(f'Max Items: {self.max_items}')
        button_layout.addWidget(max_items_label)

        main_layout.addLayout(button_layout)

        central_widget = QWidget()
        central_widget.setLayout(main_layout)
        self.setCentralWidget(central_widget)

        self.populate_list()

    def show_keybindings_dialog(self):
        dialog = QDialog(self)
        dialog.setWindowTitle("Configure Key Bindings")
        layout = QVBoxLayout()
        
        form_layout = QVBoxLayout()
        
        self.key_edits = {}
        for name, binding in self.keybindings.items():
            hbox = QHBoxLayout()
            label = QLabel(f"{name.replace('_', ' ').title()}:")
            edit = QLineEdit(binding)
            self.key_edits[name] = edit
            hbox.addWidget(label)
            hbox.addWidget(edit)
            form_layout.addLayout(hbox)
        
        layout.addLayout(form_layout)
        
        btn_box = QHBoxLayout()
        save_btn = QPushButton("Save")
        save_btn.clicked.connect(lambda: self.save_keybindings_from_dialog(dialog))
        cancel_btn = QPushButton("Cancel")
        cancel_btn.clicked.connect(dialog.reject)
        btn_box.addWidget(save_btn)
        btn_box.addWidget(cancel_btn)
        
        layout.addLayout(btn_box)
        dialog.setLayout(layout)
        dialog.exec_()

    def save_keybindings_from_dialog(self, dialog):
        for name, edit in self.key_edits.items():
            self.keybindings[name] = edit.text()
        self.save_keybindings()
        self.setup_global_hotkeys()
        dialog.accept()
        QMessageBox.information(self, "Success", "Key bindings saved. Restart application to apply changes.")

    def setup_system_tray(self):
        self.tray_icon = QSystemTrayIcon(self)
        self.tray_icon.setIcon(QIcon.fromTheme('edit-copy'))
        
        tray_menu = QMenu()
        show_action = QAction('Show', self)
        show_action.triggered.connect(self.show)
        config_action = QAction('Configure Key Bindings', self)
        config_action.triggered.connect(self.show_keybindings_dialog)
        quit_action = QAction('Quit', self)
        quit_action.triggered.connect(QApplication.quit)
        
        tray_menu.addAction(show_action)
        tray_menu.addAction(config_action)
        tray_menu.addAction(quit_action)
        
        self.tray_icon.setContextMenu(tray_menu)
        self.tray_icon.show()

    def start_monitoring(self):
        self.clipboard_timer = QTimer(self)
        self.clipboard_timer.timeout.connect(self.check_clipboard)
        self.clipboard_timer.start(500)

    def check_clipboard(self):
        mime_data = self.clipboard.mimeData()
        
        if mime_data.hasText():
            text = mime_data.text()
            self.add_item(text, 'text')
        elif mime_data.hasImage():
            image = mime_data.imageData()
            qimage = image.convertToFormat(QImage.Format_RGBA8888)
            image_bytes = qimage.bits().asstring(qimage.byteCount())
            self.add_item(image_bytes, 'image')

    def add_item(self, content, content_type):
        item = ClipboardItem(content, content_type)
        
        if any(existing.id == item.id for existing in self.history):
            return
        
        self.history.insert(0, item)
        
        if len(self.history) > self.max_items:
            self.history = self.history[:self.max_items]
        
        self.populate_list()
        self.save_config()

    def populate_list(self):
        self.clip_list.clear()
        
        for item in self.history:
            list_item = QListWidgetItem()
            
            if item.type == 'text':
                display_text = item.content[:50] + '...' if len(item.content) > 50 else item.content
                list_item.setText(display_text)
            elif item.type == 'image':
                qimage = QImage.fromData(item.content)
                pixmap = QPixmap.fromImage(qimage).scaled(
                    100, 100, Qt.KeepAspectRatio, Qt.SmoothTransformation
                )
                list_item.setIcon(QIcon(pixmap))
                list_item.setText('Image')
            
            self.clip_list.addItem(list_item)

    def restore_item(self, item):
        index = self.clip_list.row(item)
        selected_item = self.history[index]
        
        if selected_item.type == 'text':
            pyperclip.copy(selected_item.content)
        elif selected_item.type == 'image':
            qimage = QImage.fromData(selected_item.content)
            mime_data = QMimeData()
            mime_data.setImageData(qimage)
            self.clipboard.setMimeData(mime_data)

    def clear_history(self):
        self.history.clear()
        self.clip_list.clear()
        self.save_config()

    def load_config(self):
        try:
            with open(self.config_path, 'r') as f:
                config = json.load(f)
                self.history = [ClipboardItem.from_dict(item) for item in config.get('history', [])]
                self.max_items = config.get('max_items', 10)
        except (FileNotFoundError, json.JSONDecodeError):
            self.history = []

    def save_config(self):
        config = {
            'history': [item.to_dict() for item in self.history],
            'max_items': self.max_items
        }
        with open(self.config_path, 'w') as f:
            json.dump(config, f, indent=2)

    def closeEvent(self, event):
        if self.listener:
            self.listener.stop()
        event.accept()

def main():
    if 'DISPLAY' not in os.environ:
        os.environ['DISPLAY'] = ':0'

    app = QApplication(sys.argv)
    
    if sys.platform.startswith('linux'):
        app.setApplicationName('Clipboard Manager')
        app.setDesktopFileName('clipboard-manager')
    
    manager = ClipboardManager()
    manager.show()
    sys.exit(app.exec_())

if __name__ == '__main__':
    main()