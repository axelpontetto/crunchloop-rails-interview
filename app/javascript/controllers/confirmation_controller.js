import { Controller } from "@hotwired/stimulus"

// Replaces Turbo's native confirm() dialog with a styled modal. Any element with
// data-turbo-confirm="..." triggers this; the message is shown in the modal and
// the action only proceeds if the user confirms.
export default class extends Controller {
  static targets = ["modal", "message", "confirmButton"]

  connect() {
    if (window.Turbo) {
      window.Turbo.setConfirmMethod((message) => this.ask(message))
    }
  }

  ask(message) {
    this.messageTarget.textContent = message
    this.open()
    this.confirmButtonTarget.focus()
    return new Promise((resolve) => { this.resolve = resolve })
  }

  confirm() { this.settle(true) }
  cancel() { this.settle(false) }

  // Allow Escape to cancel.
  keydown(event) {
    if (event.key === "Escape") this.settle(false)
  }

  settle(value) {
    this.close()
    if (this.resolve) {
      this.resolve(value)
      this.resolve = null
    }
  }

  open() {
    this.modalTarget.classList.remove("hidden")
    this.modalTarget.classList.add("flex")
  }

  close() {
    this.modalTarget.classList.add("hidden")
    this.modalTarget.classList.remove("flex")
  }
}
