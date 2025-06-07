package test

import "core:fmt"
import "core:os"

main :: proc() {
    fmt.println("Hellope!")
    t := os.get_env("TEST")
    fmt.printfln("get_env: %s", t)
}
