import { Controller } from "@hotwired/stimulus"

// Tracks which todo list is "selected" and keeps the highlight in sync on the
// client. The right pane is loaded via a Turbo Frame and rows are re-rendered by
// Turbo Streams (inline edit, create), so the selection must survive those swaps.
export default class extends Controller {
  static targets = ["row"]

  static SELECTED = ["border-indigo-400", "bg-indigo-50"]
  static UNSELECTED = ["border-slate-200", "hover:bg-slate-50"]

  // Click on a list name → select that row.
  select(event) {
    const row = event.currentTarget.closest("[data-selection-target='row']")
    if (row) this.selectRow(row)
  }

  // Called whenever a row enters the DOM, including after a Turbo Stream swap.
  rowTargetConnected(row) {
    if (row.classList.contains("bg-indigo-50")) {
      // Server rendered this row as selected (initial load / newly created list).
      this.selectRow(row)
    } else if (this.frameId(row) === this.selectedId) {
      // A previously-selected row was re-rendered (e.g. inline edit) — re-highlight it.
      this.applyState(row, true)
    }
  }

  selectRow(row) {
    this.selectedId = this.frameId(row)
    this.rowTargets.forEach((other) => this.applyState(other, other === row))
  }

  applyState(row, selected) {
    const { SELECTED, UNSELECTED } = this.constructor
    row.classList.remove(...(selected ? UNSELECTED : SELECTED))
    row.classList.add(...(selected ? SELECTED : UNSELECTED))
  }

  frameId(row) {
    const frame = row.closest("turbo-frame")
    return frame && frame.id
  }
}
