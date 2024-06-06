import curses
import curses.textpad
import json

import utils

class OptionsMenu:
  def __init__(self, window, schema, options):
    self.window = window
    self.schema = schema
    self.options = options
    self.selection = 0

    self.init_options()

    #the window is assumed to have a border
    self.height, self.width = self.window.getmaxyx()
  
  def init_options(self):
    for option_id, option_schema in self.schema.items():
      if not option_id in self.options:
        self.options[option_id] = self.schema[option_id]["default"]
  
  def edit_options(self):
    while True:
      self.show_options()
      key = self.window.getch()
      
      if key == curses.KEY_DOWN and self.selection < len(self.schema)-1:
        self.selection += 1
      elif key == curses.KEY_UP and self.selection > 0:
        self.selection -= 1
      elif key == curses.KEY_ENTER or key == 10 or key == 13:
        self.set_value()
      elif key == 113: #q
        return self.options
  
  #display a scrolling selector
  def show_options(self):
    usable_height = self.height - 4
    offset = (self.selection // usable_height) * usable_height

    self.window.erase()
    self.window.border()
    self.window.addstr(1, 1, "Edit options:")
    self.window.addstr(2, 0, utils.horizontal_line(self.width))
  
    for i, (option_id, option_schema) in enumerate(self.schema.items()):
      if i < offset or i-offset >= usable_height: 
        continue

      option_value = self.options[option_id]
      line_text = f"{option_schema['name']}: {option_value}"

      self.window.addstr(i-offset+3, 1, line_text)
      if i == self.selection:
        self.window.chgat(i-offset+3, 1, self.width-2, curses.A_REVERSE)
      else:
        self.window.chgat(i-offset+3, 1, self.width-2, curses.A_NORMAL)
    
    self.window.refresh()
  
  def set_value(self):
    option_id = list(self.schema.keys())[self.selection]
    self.options[option_id] = self.choose_value(option_id)
  
  def choose_value(self, option_id):
    option_schema = self.schema[option_id]
    option_value = self.options[option_id]

    if option_schema["type"] == "bool":
      return not option_value
    
    elif option_schema["type"] == "str":
      return self.choose_string(f"New value for {option_id}:", option_value)
    
    elif option_schema["type"] == "int":
      text = ""
      while not utils.is_int(text):
        text = self.choose_string(f"New value for {option_id}:", option_value)
      return int(text)

  def choose_string(self, prompt, default):
    self.window.erase()
    self.window.border()
    self.window.addstr(1, 1, prompt)
    self.window.addstr(2, 0, utils.horizontal_line(self.width))
    self.window.refresh()

    curses.curs_set(1)
    textbox_window = self.window.derwin(1, self.width - 2, 3, 1)
    if default is not None:
      textbox_window.addstr(str(default))
    textbox = curses.textpad.Textbox(textbox_window, insert_mode=True)
    text = textbox.edit().replace("\x00", "").strip()

    curses.curs_set(0)
    return text