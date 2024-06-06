import curses
import curses.panel
import time
import traceback
import os
import sys

import disks
import utils
import settings
import menu.options

class Bootloader:
  def init(self):
    self.setup_curses()
    self.setup_windows()
    self.all_partitions = disks.get_all_partitions()
    self.pick_os()
    self.destroy_curses()
  
  def pick_os(self):
    selected_item = 0

    while True:
      self.show_disks(selected_item)
      key = self.entries_window.getch()
      
      if key == curses.KEY_DOWN and selected_item < len(self.all_partitions)-1:
        selected_item += 1
      elif key == curses.KEY_UP and selected_item > 0:
        selected_item -= 1
      elif key == curses.KEY_ENTER or key == 10 or key == 13:
        self.boot_entry(selected_item)
      elif key == 115: #s
        self.enter_shell()
      elif key == 101: #e
        self.edit_entry(selected_item)
  
  def edit_entry(self, selected_item):
    partition = self.all_partitions[selected_item]
    schema_name = partition["schema_name"]
    schema = settings.schemas[schema_name]

    self.options_panel.show()
    options_menu = menu.options.OptionsMenu(self.options_window, schema, {})
    new_options = options_menu.edit_options()
    self.options_panel.hide()
    curses.panel.update_panels()
    
  def enter_shell(self):
    self.destroy_curses()
    print("Entering a shell")
    utils.output_file.write_text('enable_debug_console "$TTY1"')
    os._exit(0)
  
  def boot_entry(self, selected_item):
    self.destroy_curses()
    partition = self.all_partitions[selected_item]
    
    if partition["type"] == "ChromeOS rootfs":
      self.boot_chrome_os(partition)
    else:
      self.boot_regular(partition)
    
    os._exit(0)
  
  def boot_regular(self, partition):
    print(f"Booting {partition['name']} on {partition['device']}")
    output_cmd = f"boot_target {partition['device']}"
    utils.output_file.write_text(output_cmd)
  
  def boot_chrome_os(self, partition):
    print(f"Booting Chrome OS {partition['name']} on {partition['device']}")
    output_cmd = f"boot_chromeos {partition['device']}"
    utils.output_file.write_text(output_cmd)
  
  def setup_windows(self):
    self.title_window = curses.newwin(3, self.cols, 0, 0)
    self.centered_text(self.title_window, 1, "Shimboot OS Selector")
    self.title_window.refresh()

    self.entries_window = curses.newwin(self.rows-7, self.cols-8, 3, 4)
    self.entries_window.keypad(True)
    self.entries_window.border()
    self.entries_window.refresh()

    self.footer_window = curses.newwin(2, self.cols-10, self.rows - 3, 5)
    self.footer_window.addstr(0, 0, "Use the arrow keys to select an entry. Press [enter] to boot the selected item.")
    self.footer_window.addstr(1, 0, "Use [e] to edit an entry, [s] to enter a shell, and [esc] to shut down the system.")
    self.footer_window.refresh()

    rows, cols = self.entries_window.getmaxyx()
    options_width = cols / 2
    x1 = int(cols / 2 - options_width / 2)
    x2 = int(cols / 2 + options_width / 2)
    win_cols = x2 - x1
    win_rows = int(rows / 1.5)
    self.options_window = curses.newwin(win_rows, win_cols, 7, x1)
    self.options_window.keypad(True)
    self.options_window.border()

    self.setup_panels()
  
  def setup_panels(self):
    self.title_panel = curses.panel.new_panel(self.title_window)
    self.entries_panel = curses.panel.new_panel(self.entries_window)
    self.footer_panel = curses.panel.new_panel(self.footer_window)
    self.options_panel = curses.panel.new_panel(self.options_window)
    self.options_panel.hide()
  
  def setup_curses(self):
    self.screen = curses.initscr()
    self.rows, self.cols = self.screen.getmaxyx()
    self.screen.nodelay(1)
    curses.curs_set(0)
    curses.noecho()
    curses.cbreak()
  
  def destroy_curses(self):
    curses.curs_set(1)
    curses.nocbreak()
    curses.echo()
    curses.endwin()
    print("\x1b[2J\x1b[H", end="")
  
  def centered_text(self, window, y, text):
    cols = self.screen.getmaxyx()[1]
    x = int(cols/2 - len(text)/2)
    window.addstr(y, x, text)
  
  def show_disks(self, selected_item):
    width = self.entries_window.getmaxyx()[1]
    for i, partition in enumerate(self.all_partitions):
      partition_text = f"{partition['name']} on {partition['device']}"
      self.entries_window.addstr(i+1, 2, partition_text)
      if i == selected_item:
        self.entries_window.chgat(i+1, 1, width-2, curses.A_REVERSE)
      else:
        self.entries_window.chgat(i+1, 1, width-2, curses.A_NORMAL)
      i += 1
    self.entries_window.refresh()
