import curses
import curses.textpad

import utils

#this is currently a WIP and is untested
class OptionsMenu:
  def __init__(self, window, schema, options):
    self.window = window
    self.schema = schema
    self.options = options
    self.selection = 0

    #the window is assumed to have a border already
    self.height, self.width = self.window.getmaxyx()
  
  #main loop
  def main(self):
    while True:
      self.show_options()
      key = self.entries_window.getch()
      
      if key == curses.KEY_DOWN and self.selection < len(self.options)-1:
        self.selection += 1
      elif key == curses.KEY_UP and self.selection > 0:
        self.selection -= 1
      elif key == curses.KEY_ENTER or key == 10 or key == 13:
        self.choose_value()
      elif key == 27: #esc
        break

  #display a scrolling selector
  def show_options(self):
    offset = max(0, self.selection - self.height + 2)
  
    for i, (option_id, option_schema) in enumerate(self.schema.items()):
      if i < offset or i-offset > self.height-2: 
        continue

      if option_id in self.options:
        option_value = self.options[option_id]
      else:
        option_value = option_schema["default"]
      line_text = f"{option_schema['name']}: {option_value}"

      if i == self.selection:
        self.window.chgat(i-offset+1, 1, self.width-2, curses.A_REVERSE)
      else:
        self.window.chgat(i-offset+1, 1, self.width-2, curses.A_NORMAL)
  
  def choose_value(self):
    option_id = list(self.schema.keys())[self.selection]
    option_schema = list(self.schema.values())[self.selection]
    option_value = self.options[option_id]

    if option_schema["type"] == "bool":
      return not option_value
    
    elif option_schema["type"] == "str":
      return choose_string(f"Type a new value for {option_id}:")
    
    elif option_schema["type"] == "float": 
      while True:
        text = choose_string(f"Type a new value for {option_id}:")
        if utils.is_float(text):
          return float(text)

  def choose_string(self, prompt, lines=1):
    utils.clear_window(self.window)
    self.window.addstr(1, 1, prompt)
    textbox_window = self.window.subwin(2, 1, self.width - 2, lines)
    textbox = curses.textpad.Textbox(textbox, insert_mode=True)
    self.window.refresh()
    text = textbox.edit()
    utils.clear_window(self.window)
    return text