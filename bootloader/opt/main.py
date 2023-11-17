import curses
import curses.panel
import disks
import time
import traceback

class Bootloader:
  def init(self):
    self.setup_curses()
    self.setup_windows()
    self.show_disks()
    time.sleep(10)
    self.destroy_curses()
  
  def setup_windows(self):
    self.title_window = curses.newwin(3, self.cols, 0, 0)
    self.centered_text(self.title_window, 1, "Shimboot OS Selector")
    self.title_window.refresh()

    self.entries_window = curses.newwin(self.rows-7, self.cols-8, 3, 4)
    self.entries_window.border()
    self.entries_window.refresh()

    self.footer_window = curses.newwin(2, self.cols-10, self.rows - 3, 5)
    self.footer_window.addstr(0, 0, "Use the arrow keys to select an entry. Press [enter] to boot the selected item.")
    self.footer_window.addstr(1, 0, "Use [e] to edit an entry, [s] to enter a shell, and [esc] to shut down the system.")
    self.footer_window.refresh()
  
  def setup_curses(self):
    self.screen = curses.initscr()
    self.rows, self.cols = self.screen.getmaxyx()
    self.screen.keypad(True)
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
  
  def show_disks(self):
    all_partitions = disks.get_all_partitions()
    y = 1
    for disk, partitions in all_partitions.items():
      for partition in partitions:
        self.entries_window.addstr(y, 2, f"{partition['name']} on {disk}")
        y += 1
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