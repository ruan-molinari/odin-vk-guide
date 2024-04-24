package main

import "core:fmt"

main :: proc() {

  err := engine_init()
  if err != nil {
    fmt.println(err)
  }
  defer engine_cleanup()

  engine_run()

}
