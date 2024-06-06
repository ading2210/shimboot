import menu.bootloader

if __name__ == "__main__":
  try:
    main_menu = menu.bootloader.Bootloader()
    main_menu.init()
  except KeyboardInterrupt:
    main_menu.destroy_curses()
  except:
    main_menu.destroy_curses()
    print(traceback.format_exc())
    sys.exit(1)