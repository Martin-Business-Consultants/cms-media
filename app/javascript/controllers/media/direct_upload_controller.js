import { Controller } from "@hotwired/stimulus"

// Shows each file's progress while Active Storage uploads it straight to
// storage (a file field with direct_upload: true). The events come from
// @rails/activestorage and bubble from the field.
export default class extends Controller {
  static targets = [ "input", "list" ]

  connect() {
    this.element.addEventListener("direct-upload:initialize", this.#initialize)
    this.element.addEventListener("direct-upload:progress", this.#progress)
    this.element.addEventListener("direct-upload:error", this.#error)
    this.element.addEventListener("direct-upload:end", this.#end)
  }

  disconnect() {
    this.element.removeEventListener("direct-upload:initialize", this.#initialize)
    this.element.removeEventListener("direct-upload:progress", this.#progress)
    this.element.removeEventListener("direct-upload:error", this.#error)
    this.element.removeEventListener("direct-upload:end", this.#end)
  }

  #initialize = (event) => {
    const { id, file } = event.detail
    const item = document.createElement("li")
    item.id = `direct-upload-${id}`
    item.className = "flex items-center gap-2"

    const name = document.createElement("span")
    name.className = "min-w-0 flex-1 truncate"
    name.textContent = file.name

    const bar = document.createElement("progress")
    bar.className = "w-24 shrink-0"
    bar.max = 100
    bar.value = 0

    item.append(name, bar)
    this.listTarget.append(item)
    this.listTarget.hidden = false
  }

  #progress = (event) => {
    const bar = this.#item(event)?.querySelector("progress")
    if (bar) bar.value = event.detail.progress
  }

  #error = (event) => {
    event.preventDefault()
    const item = this.#item(event)
    if (item) {
      item.classList.add("text-red-600")
      item.title = event.detail.error
    }
  }

  #end = (event) => {
    const bar = this.#item(event)?.querySelector("progress")
    if (bar) bar.value = 100
  }

  #item(event) {
    return this.listTarget.querySelector(`#direct-upload-${event.detail.id}`)
  }
}
