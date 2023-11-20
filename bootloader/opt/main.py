import curses
import curses.panel
import disks
import time
import traceback

class Bootloader:
  def init(self):
    self.setup_curses()
    self.setup_windows()
    self.all_partitions = disks.get_all_partitions()
    self.main()
    self.destroy_curses()
  
  def main(self):
    selected = 0
    while True:
      self.show_disks(selected)
      char = self.entries_window.getch()
      
      if char == curses.KEY_DOWN and selected < len(self.all_partitions)-1:
        selected += 1
      elif char == curses.KEY_UP and selected > 0:
        selected -= 1
  
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
  
  def setup_curses(self):
    self.screen = curses.initscr()
    self.rows, self.cols = self.screen.getmaxyx()
    self.screen.nodelay(1)
    curses.curs_set(0)
    curses.noecho()
    curses.cbreak()
  
  def destroy_curses(self):
    self.screen.keypad(False)
    curses.curs_set(1)
    curses.nocbreak()
    curses.echo()
    curses.endwin()
  
  def centered_text(self, window, y, text):
    cols = self.screen.getmaxyx()[1]
    x = int(cols/2 - len(text)/2)
    window.addstr(y, x, text)
  
  def show_disks(self, selected=0):
    for i, (disk, partitions) in enumerate(self.all_partitions.items()):
      for partition in partitions:
        partition_text = f"{partition['name']} on {disk}"
        if i == selected:
          self.entries_window.addstr(i+1, 2, f"{partition['name']} on {disk}", curses.A_REVERSE)
        else:
          self.entries_window.addstr(i+1, 2, f"{partition['name']} on {disk}", curses.A_NORMAL)
    self.entries_window.refresh()

if __name__ == "__main__":
  try:
    bootloader = Bootloader()
    bootloader.init()
  except KeyboardInterrupt:
    bootloader.destroy_curses()
  except:
    bootloader.destroy_curses()
    print(traceback.format_exc())