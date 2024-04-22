package main

main :: proc() {

  engine_init()
  defer engine_cleanup()

  engine_run()

}
