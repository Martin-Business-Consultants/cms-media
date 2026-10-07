import { Controller } from "@hotwired/stimulus"

// The shared asset picker dialog. Picking an asset tells the field that
// opened it (asset-field controller) and closes.
export default class extends Controller {
  pick(event) {
    const asset = event.currentTarget
    window.dispatchEvent(new CustomEvent("asset-picker:picked", {
      detail: {
        field: this.element.dataset.forField,
        id: asset.dataset.assetId,
        name: asset.dataset.assetName,
        thumb: asset.querySelector(".media-thumb")?.innerHTML
      }
    }))
    this.close()
  }

  close() {
    this.element.close()
  }
}
