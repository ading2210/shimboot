import curses
import curses.panel
import disks
import time

class Bootloader:
  def init(self):
    self.setup_curses()
    self.setup_windows()
    time.sleep(3)
    self.destroy_curses()
  
  def setup_windows(self):
    self.title_window = curses.newwin(3, self.cols, 0, 0)
    self.centered_text(self.title_window, 1, "Shimboot OS Selector")
    self.title_window.refresh()
  
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

if __name__ == "__main__":
  try:
    bootloader = Bootloader()
    bootloader.init()
  except KeyboardInterrupt:
    bootloader.destroy_curses()