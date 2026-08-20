import { Controller } from "@hotwired/stimulus"
import consumer from "channels/consumer"

// Talks to DocumentChannel (see app/channels/document_channel.rb for the
// full wire protocol). Deliberately thin: every position decision for
// the CRDT is made server-side by Fugue — this controller never walks a
// tree itself, it just applies whatever resolved index the server sends.
//
// No optimistic local model beyond what the browser already does
// natively when you type into a textarea. This controller's job is: (1)
// diff the textarea's value on input to figure out what the user just
// did, and tell the server; (2) apply incoming remote ops by splicing
// them into the textarea directly; (3) recognize when an incoming op is
// just confirming one of ITS OWN pending sends (via client_op_id) and
// skip re-applying it, since the browser already shows it.
export default class extends Controller {
  static targets = ["textarea", "status"]
  static values = { documentId: Number }

  connect() {
    this.pendingOps = new Map()
    this.nextOpId = 0
    this.lastKnownValue = this.textareaTarget.value

    this.subscribe()
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  subscribe() {
    this.subscription = consumer.subscriptions.create(
      { channel: "DocumentChannel", document_id: this.documentIdValue },
      {
        connected: () => this.setStatus("Connected"),
        disconnected: () => this.setStatus("Disconnected — reconnecting…"),
        rejected: () => this.setStatus("Couldn't open this document"),
        received: (data) => this.handleReceived(data),
      },
    )
  }

  handleReceived(data) {
    switch (data.type) {
      case "init":
        this.textareaTarget.value = data.text
        this.lastKnownValue = data.text
        break
      case "insert":
        this.applyIfNotOwnEcho(data, () => this.spliceInsert(data.index, data.value))
        break
      case "delete":
        this.applyIfNotOwnEcho(data, () => this.spliceDelete(data.index))
        break
    }
  }

  // If this op is confirming one WE sent, the browser already shows the
  // edit — just clear the pending marker, don't touch the DOM (touching
  // it again would duplicate the character or fight the user's live
  // cursor). Otherwise it's a remote edit and needs to be spliced in.
  applyIfNotOwnEcho(data, applyFn) {
    if (data.client_op_id && this.pendingOps.has(data.client_op_id)) {
      this.pendingOps.delete(data.client_op_id)
      return
    }
    applyFn()
  }

  spliceInsert(index, value) {
    const el = this.textareaTarget
    const { selectionStart, selectionEnd } = el
    el.value = el.value.slice(0, index) + value + el.value.slice(index)
    this.lastKnownValue = el.value

    // Keep the user's own cursor/selection stable relative to a remote
    // edit landing before it.
    const shift = index <= selectionStart ? value.length : 0
    el.selectionStart = selectionStart + shift
    el.selectionEnd = selectionEnd + shift
  }

  spliceDelete(index) {
    const el = this.textareaTarget
    const { selectionStart, selectionEnd } = el
    el.value = el.value.slice(0, index) + el.value.slice(index + 1)
    this.lastKnownValue = el.value

    const shift = index < selectionStart ? -1 : 0
    el.selectionStart = Math.max(0, selectionStart + shift)
    el.selectionEnd = Math.max(0, selectionEnd + shift)
  }

  // Fired on the textarea's `input` event (wire this up in the view:
  // data-action="input->document-editor#onInput"). Diffs the new value
  // against the last known one via common-prefix/common-suffix, which is
  // enough to turn "what changed" into the minimal insert and/or delete
  // — covers typing, backspace/delete, paste, and select-and-replace.
  onInput(event) {
    const newValue = event.target.value
    const oldValue = this.lastKnownValue
    this.lastKnownValue = newValue

    const { start, deletedLength, inserted } = diff(oldValue, newValue)

    for (let i = 0; i < deletedLength; i++) {
      this.sendIntent({ type: "delete", index: start })
    }
    if (inserted.length > 0) {
      this.sendIntent({ type: "insert", index: start, value: inserted })
    }
  }

  sendIntent(intent) {
    const client_op_id = String(this.nextOpId++)
    this.pendingOps.set(client_op_id, true)
    this.subscription.send({ ...intent, client_op_id })

    // Best-effort recovery, not a full reconciliation protocol: if the
    // server silently dropped this op (a stale-index race — see
    // DocumentChannel#apply_intent!'s rescue), nothing ever confirms it,
    // and this client has now quietly drifted from the canonical
    // document with no other signal that happened. Re-subscribing pulls
    // a fresh "init" and resets to the server's actual current state.
    // This does mean a rare, hard resync rather than a graceful merge —
    // that trade-off is deliberate for what this project needs, not an
    // oversight.
    setTimeout(() => {
      if (this.pendingOps.has(client_op_id)) {
        this.pendingOps.delete(client_op_id)
        this.subscription.unsubscribe()
        this.subscribe()
      }
    }, 4000)
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }
}

function diff(oldValue, newValue) {
  let start = 0
  const maxPrefix = Math.min(oldValue.length, newValue.length)
  while (start < maxPrefix && oldValue[start] === newValue[start]) start++

  let oldEnd = oldValue.length
  let newEnd = newValue.length
  while (oldEnd > start && newEnd > start && oldValue[oldEnd - 1] === newValue[newEnd - 1]) {
    oldEnd--
    newEnd--
  }

  return { start, deletedLength: oldEnd - start, inserted: newValue.slice(start, newEnd) }
}
