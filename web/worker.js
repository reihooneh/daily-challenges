// Runs the planner off the main thread, so the page never freezes and a
// search that takes too long can be stopped by terminating this worker.
/* global Go, pickTwoSolve */
importScripts('wasm_exec.js');

const ready = (async () => {
  const go = new Go();
  const response = await fetch('picktwo.wasm');
  if (!response.ok) throw new Error('could not load the planner');
  const { instance } = await WebAssembly.instantiate(await response.arrayBuffer(), go.importObject);
  go.run(instance); // never resolves: the Go program stays alive to serve calls
})();

self.onmessage = async (event) => {
  const { id, text } = event.data;
  try {
    await ready;
    // The planner checks sizes itself; this stops an oversized string before
    // it is even copied into WebAssembly memory.
    if (typeof text !== 'string' || text.length > 70000) {
      self.postMessage({ id, json: '{"status":"error","error":"That is too much text for the planner."}' });
      return;
    }
    self.postMessage({ id, json: pickTwoSolve(text) });
  } catch {
    self.postMessage({ id, json: '{"status":"error","error":"The planner could not start in this browser."}' });
  }
};
