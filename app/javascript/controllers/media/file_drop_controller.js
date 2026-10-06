import { Controller } from "@hotwired/stimulus"

// Files dropped on the file manager upload through the same forms the buttons
// use, so Active Storage's direct upload and its progress list do the work:
// ordinary files into the folder being looked at (or the folder they were
// dropped on, in the tree or the grid), and a zip dropped on its own into the
// zip form, to be unpacked.
export default class extends Controller {
  static targets = [ "overlay", "filesInput", "filesFolder", "zipInput", "zipFolder", "zipBox", "message" ]

  #depth = 0

  enter(event) {
    if (!this.#carriesFiles(event)) return
    event.preventDefault()
    this.#depth++
    this.overlayTarget.hidden = false
  }

  over(event) {
    if (!this.#carriesFiles(event)) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "copy"
    this.#highlight(event.target.closest("[data-drop-folder]"))
  }

  leave(event) {
    if (!this.#carriesFiles(event)) return
    this.#depth = Math.max(0, this.#depth - 1)
    if (this.#depth === 0) this.#reset()
  }

  drop(event) {
    if (!this.#carriesFiles(event)) return
    event.preventDefault()
    const folder = event.target.closest("[data-drop-folder]")?.dataset.dropFolder
    const files = Array.from(event.dataTransfer.files)
    this.#reset()

    const zips = files.filter(file => this.#isZip(file))
    if (zips.length === 1 && files.length === 1 && this.hasZipInputTarget) {
      this.#submit(this.zipInputTarget, this.hasZipFolderTarget ? this.zipFolderTarget : null, zips, folder)
      if (this.hasZipBoxTarget) this.zipBoxTarget.open = true
    } else {
      const ordinary = files.filter(file => !this.#isZip(file))
      if (zips.length) this.#say("Zips unpack one at a time: drop a zip on its own.")
      if (ordinary.length) this.#submit(this.filesInputTarget, this.filesFolderTarget, ordinary, folder)
    }
  }

  // The "Choose files" button in the ready drop zone (+ New › Media).
  choose() {
    this.filesInputTarget.click()
  }

  #submit(input, folderField, files, folder) {
    const transfer = new DataTransfer()
    files.forEach(file => transfer.items.add(file))
    input.files = transfer.files
    if (folder && folderField) folderField.value = folder
    input.form.requestSubmit()
  }

  #carriesFiles(event) {
    return Array.from(event.dataTransfer?.types || []).includes("Files")
  }

  #isZip(file) {
    return file.type === "application/zip" || file.type === "application/x-zip-compressed" || /\.zip$/i.test(file.name)
  }

  #highlight(target) {
    this.element.querySelectorAll(".file-drop__folder--over").forEach(el => { if (el !== target) el.classList.remove("file-drop__folder--over") })
    target?.classList.add("file-drop__folder--over")
  }

  #reset() {
    this.#depth = 0
    this.overlayTarget.hidden = true
    this.#highlight(null)
  }

  #say(text) {
    if (!this.hasMessageTarget) return
    this.messageTarget.textContent = text
    this.messageTarget.hidden = false
  }
}
