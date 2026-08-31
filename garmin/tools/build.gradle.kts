plugins {
    kotlin("jvm") version "1.9.24"
    application
}
kotlin { jvmToolchain(21) }
application { mainClass.set("TzRulesKt") }
