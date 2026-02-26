/*LINvis.js
Written by Keith Jolley
Copyright (c) 2026, University of Oxford
E-mail: keith.jolley@biology.ox.ac.uk
*/

/*Inspired and extensively modified from Zoomable Circle Packing 
(https://observablehq.com/@d3/zoomable-circle-packing).
Written by Mike Bostock.
Copyright 2018-2023 Observable, Inc.

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

Version 1.0.0.
*/



(async function() {
	const width = 960, height = 960;
	const diameter = Math.min(width, height) - 20;
	let labelDepth = 1;              // which depth to label
	const initialLabelDepth = 1;
	const SMOOTH_ZOOM_MAX_NODES = 5000; // changeable threshold for using smoothZoomTo()
	const waiting = document.getElementById('waiting');

	// ---------- Flexible data loader ----------
	// Accepts an uploaded file (id="linvis-file") or a URL param ?data=NAME (or ?file=NAME)
	// which is interpreted as a basename and loaded from /tmp/{basename}.json.
	async function loadData() {
		// 1) File input (if user has chosen a file)
		const fileInput = document.getElementById("linvis-file");
		if (fileInput && fileInput.files && fileInput.files[0]) {
			try {
				const txt = await fileInput.files[0].text();
				return JSON.parse(txt);
			} catch (err) {
				// explicit failure so caller shows the error message
				console.warn("LINvis: failed to read/parse selected file:", err);
				throw err;
			}
		}

		// 2) URL parameter: ?job=BIGSdb_...  (treat as basename -> /tmp/{basename}.json)
		try {

			const params = new URLSearchParams(window.location.search);
			const key = params.get("data") || params.get("job");
			if (key) {
				waiting.style.display = 'block';
				// sanitize to basename (strip any slashes) and escape
				const basename = String(key).split('/').pop();
				const path = "/tmp/" + encodeURIComponent(basename) + ".json";
				const resp = await fetch(path);
				if (!resp.ok) throw new Error("HTTP " + resp.status + " when fetching " + path);
				return await resp.json();
			}
		} catch (err) {
			console.warn("LINvis: failed to fetch JSON from URL param:", err);
			throw err;
		}

		// 3) No data provided
		throw new Error("No data provided (no file selected and no ?data=... URL parameter).");
	}

	// --- Simple wrapper toggle approach (uses #linvis-file-wrapper) ---
	const _linvis_params = new URLSearchParams(window.location.search);
	const _linvis_key = _linvis_params.get("data") || _linvis_params.get("job");
	const hasRemoteJob = Boolean(_linvis_key);

	// Hide wrapper if remote job present (no file chooser)
	(function toggleWrapperVisibility() {
		const wrapper = document.getElementById("linvis-file-wrapper");
		if (!wrapper) return;
		wrapper.style.display = hasRemoteJob ? "none" : "";
	})();

	let data;
	try {
		data = await loadData();
	} catch (err) {
		// ensure waiting message is hidden on failure so UI does not stay blocked
		try { if (waiting) waiting.style.display = 'none'; } catch (e) { /* ignore */ }
		// If NO remote job/data param was supplied,
		// show the file selector — and if the failure was from a selected file, report the parse error to the user.
		// If NO remote job/data param was supplied:
		if (!hasRemoteJob) {
			const wrapper = document.getElementById("linvis-file-wrapper");
			if (wrapper) {
				wrapper.style.display = "";

				const inp = wrapper.querySelector("#linvis-file");
				const hadFile = inp && inp.files && inp.files[0];

				// Only show an error if the user actually selected a file
				if (hadFile) {
					try {
						const ctrl = document.querySelector('.control');
						if (ctrl) {
							let note = ctrl.querySelector('.linvis-error-note');
							if (!note) {
								note = document.createElement('div');
								note.className = 'linvis-error-note';
								note.style.color = '#800';
								note.style.fontSize = '12px';
								note.style.marginTop = '6px';
								ctrl.appendChild(note);
							}
							const msgText = (err && err.message)
								? ('Failed to parse selected JSON file: ' + err.message)
								: 'Failed to parse selected JSON file (invalid JSON).';
							note.textContent = msgText;
						}
					} catch (e) { /* ignore DOM errors */ }
				}

				// Focus file input so user can retry
				if (inp && typeof inp.focus === "function") inp.focus();
			}

			return;
		}

		// If a remote job WAS requested and failed, show error + reveal selector.
		const el = document.getElementById("linvis_chart");

		let msg;
		if (hasRemoteJob && _linvis_key) {
			msg = "Failed to load data for job " + _linvis_key + ".";
		} else {
			msg = "Failed to load data.";
		}

		if (el) el.textContent = msg;

		try {
			const wrapper = document.getElementById("linvis-file-wrapper");
			if (wrapper) {
				wrapper.style.display = "";
				const inp = wrapper.querySelector("#linvis-file");
				if (inp && typeof inp.focus === "function") inp.focus();
			}

			const ctrl = document.querySelector('.control');
			if (ctrl) {
				let note = ctrl.querySelector('.linvis-error-note');
				if (!note) {
					note = document.createElement('div');
					note.className = 'linvis-error-note';
					note.style.color = '#800';
					note.style.fontSize = '12px';
					note.style.marginTop = '6px';
					ctrl.appendChild(note);
				}
				note.textContent = 'Remote load failed — choose a local .json file to continue.';
			}
		} catch (e) { /* ignore DOM errors */ }

		return;
	}


	// Build hierarchy, preserving explicit internal values (no double count)
	const root = d3.hierarchy(data);
	root.eachAfter(node => {
		if (node.data && node.data.value != null) node.value = +node.data.value;
		else if (node.children) node.value = node.children.reduce((s, c) => s + (c.value || 0), 0);
		else node.value = 0;
	});

	// --- Prune wrapper nodes that have exactly one child (but keep top-level groups) ---
	(function pruneSingletonWrappers(rootNode) {
		let pruned = 0;
		// Process bottom-up so deepest wrappers are handled first
		rootNode.eachAfter(function(node) {
			// skip root, top-level groups (depth===1) and leaves
			if (!node.parent || node.depth === 1 || !node.children || node.children.length !== 1) return;
			const child = node.children[0];
			const parent = node.parent;
			// replace the reference to `node` in parent's children with `child`
			for (let i = 0; i < parent.children.length; i++) {
				if (parent.children[i] === node) {
					parent.children[i] = child;
					child.parent = parent;
					pruned++;
					break;
				}
			}
		});

		if (pruned > 0) {
			console.log(`LINvis: pruned ${pruned} singleton wrapper node${pruned === 1 ? "" : "s"}.`);
			// Recompute values now that structure changed (preserve explicit data.value when present)
			rootNode.eachAfter(node => {
				if (node.data && node.data.value != null) node.value = +node.data.value;
				else if (node.children) node.value = node.children.reduce((s, c) => s + (c.value || 0), 0);
				else node.value = 0;
			});
		} else {
			console.debug("LINvis: pruneSingletonWrappers found no single-child wrappers to prune.");
		}
	})(root);


	d3.pack().size([diameter, diameter]).padding(2)(root);

	// Nodes + depth grouping
	const nodes = root.descendants();
	const nodesByDepth = d3.group(nodes, d => d.depth);
	const maxDepth = d3.max(nodes, d => d.depth);

	// Determine which depth to use as the "colour anchor".
	// Normally this is depth 1 (top-level groups). If root has only one child,
	// find the first depth with more than one node and use that instead.
	let colorAnchorDepth = 1;
	if ((root.children || []).length <= 1) {
		for (let d = 1; d <= Math.max(1, maxDepth); d++) {
			const arr = nodesByDepth.get(d) || [];
			if (arr.length > 1) { colorAnchorDepth = d; break; }
		}
	}

	// Build palette keys for the chosen anchor depth (colorAnchorDepth).
	const topKeys = (nodesByDepth.get(colorAnchorDepth) || []).map(c => (c.data && c.data.name) ? c.data.name : String(c.index));
	const top1Palette = d3.scaleOrdinal(d3.schemePastel1).domain(topKeys);

	// Prepare container / SVG
	const container = d3.select("#linvis_chart");
	if (container.empty()) {
		console.error("Container #linvis_chart not found.");
		return;
	}
	container.selectAll("*").remove();

	const svg = container.append("svg")
		.attr("viewBox", [0, 0, width, height])
		.style("width", "100%")
		.style("height", "auto")
		.style("touch-action", "none");

	const svgNode = svg.node();                // cached DOM node
	let svgRectCache = null;                   // cached bounding rect (updated on demand)
	function updateSvgRectCache() { svgRectCache = svgNode.getBoundingClientRect(); }
	let _linvis_resizeRaf = null;
	function onLinvisResize() {
		if (_linvis_resizeRaf) cancelAnimationFrame(_linvis_resizeRaf);
		_linvis_resizeRaf = requestAnimationFrame(() => {
			updateSvgRectCache();
			_linvis_resizeRaf = null;
		});
	}
	window.addEventListener('resize', onLinvisResize, { passive: true });
	updateSvgRectCache();

	const tx = (width - diameter) / 2;
	const g = svg.append("g").attr("transform", `translate(${tx},${tx})`);

	// Layers
	const nodeLayer = g.append("g").attr("class", "node-layer");
	const ringLayer = g.append("g").attr("class", "ring-layer");  // aggregates go here
	// persistent boundary for the root pack (kept separate so cleanup won't remove it)
	const boundary = ringLayer.append("circle")
		.attr("class", "boundary")
		.attr("fill", "none")
		.attr("stroke", "#333")
		.style("stroke-width", "1.5px")
		.style("pointer-events", "none");


	const labelLayer = g.append("g").attr("class", "label-layer");

	// Layers above nodes should not block pointer events so node groups get mouse events.
	ringLayer.style("pointer-events", "none");
	labelLayer.style("pointer-events", "none");



	// Depth input
	const depthInput = document.getElementById("depth");
	if (depthInput) {
		depthInput.min = 0;
		depthInput.max = maxDepth;
		depthInput.value = Math.min(initialLabelDepth, maxDepth);
	}

	// client -> data coordinates (for zoom-to-cursor)
	function clientToData(clientX, clientY, v = view) {
		const k = diameter / v[2];
		const svgRect = svgRectCache;
		const px = clientX - svgRect.left - ((width - diameter) / 2);
		const py = clientY - svgRect.top - ((height - diameter) / 2);
		const dataX = v[0] + (px - diameter / 2) / k;
		const dataY = v[1] + (py - diameter / 2) / k;
		return [dataX, dataY];
	}

	// Consolidated helper: compute a new view (x,y,w) for a given client center and scale factor.
	// clientX, clientY: DOM client coords (page)
	// factor: multiply current view width by this factor (e.g. >1 => zoom out, <1 => zoom in)
	// srcView: optional source view array [x,y,w] to base calculation on (defaults to current view)
	function computeViewForClientCenter(clientX, clientY, factor, srcView = view) {
		// avoid repeated lookups of svgRectCache/diameter/width/height in multiple handlers
		const svgRect = svgRectCache;
		if (!svgRect) {
			// fallback: return unmodified view if bounding rect unavailable
			return srcView.slice();
		}
		const targetW = Math.min(root.r * 4, srcView[2] * factor); // reuse previous zoom-out cap logic
		const kNew = diameter / targetW;

		// client px -> svg-local px (subtract left/top plus centring offset)
		const px = clientX - svgRect.left - ((width - diameter) / 2);
		const py = clientY - svgRect.top - ((height - diameter) / 2);

		// convert client px to data coords centered around px/py
		const cx = srcView[0] + (px - diameter / 2) / (diameter / srcView[2]);
		const cy = srcView[1] + (py - diameter / 2) / (diameter / srcView[2]);

		// compute new view origin so that data point (cx,cy) stays under clientX,clientY at new scale
		const newX = cx - (px - diameter / 2) / kNew;
		const newY = cy - (py - diameter / 2) / kNew;

		return [newX, newY, targetW];
	}


	// Create node groups and circles
	const node = nodeLayer.selectAll("g.node")
		.data(nodes)
		.join("g")
		.attr("class", "node")
		.attr("transform", d => `translate(${d.x},${d.y})`)
		.each(function(d) { d.__node_group = this; });

	// -------- Robust persistent root tooltip (no global `root` dependency) --------
	(function attachRootTooltipNoGlobals() {
		try {
			// create/reuse a fixed HTML tooltip
			let tip = document.getElementById("linvis_root_tooltip");
			if (!tip) {
				tip = document.createElement("div");
				tip.id = "linvis_root_tooltip";
				document.body.appendChild(tip);
			}
			Object.assign(tip.style, {
				position: "fixed",
				pointerEvents: "none",
				zIndex: "2147483647",
				background: "rgba(0,0,0,0.85)",
				color: "#fff",
				padding: "6px 8px",
				borderRadius: "4px",
				fontSize: "12px",
				lineHeight: "1.2",
				display: "none",
				transform: "none",
				whiteSpace: "pre-wrap",
				boxSizing: "border-box"
			});

			// find SVG and guard
			const svgNode = document.querySelector("#linvis_chart svg");
			if (!svgNode) return console.warn("LINvis: SVG not found for root tooltip fallback");

			// ensure decorative layers don't intercept pointer events and node groups accept them
			if (typeof ringLayer !== "undefined") ringLayer.style("pointer-events", "none");
			if (typeof labelLayer !== "undefined") labelLayer.style("pointer-events", "none");
			d3.selectAll("g.node").style("pointer-events", "all");

			const _rootCache = { rootG: null };

			// observe node-layer for structural changes and clear cache when it does
			try {
				const nodeLayerEl = document.querySelector("#linvis_chart g.node-layer");
				if (nodeLayerEl) {
					const mo = new MutationObserver(() => { _rootCache.rootG = null; });
					mo.observe(nodeLayerEl, { childList: true, subtree: true });
				}
			} catch (e) { /* ignore observer failures */ }

			function computeRootAndView() {
				// return cached root if present
				let rootG = _rootCache.rootG;
				if (!rootG) {
					// find root group (depth 0) once and cache it
					const all = document.querySelectorAll("g.node");
					for (let i = 0; i < all.length; i++) {
						const g = all[i];
						if (g && g.__data__ && g.__data__.depth === 0) {
							rootG = g;
							break;
						}
					}
					_rootCache.rootG = rootG || null;
				}

				if (!rootG) return null;

				const rootData = rootG.__data__;
				// prefer existing view if present in scope; otherwise fallback to root's own coords
				const viewNow = (typeof view !== "undefined" ? view : [rootData.x, rootData.y, rootData.r * 2]);
				return { rootData, viewNow, rootG };
			}

			// helper: get bounding box of visible root circle (boundary preferred)
			function getVisualCircleBBox() {
				let visualCircle = document.querySelector('circle.boundary');

				// Fallback to root group's own circle
				if (!visualCircle) {
					const rootG = Array.from(document.querySelectorAll('g.node'))
						.find(g => g && g.__data__ && g.__data__.depth === 0);
					visualCircle = rootG ? (rootG.querySelector('circle') || rootG) : null;
				}

				return visualCircle ? visualCircle.getBoundingClientRect() : null;
			}

			// helper: show/hide tip
			function showTipAt(ev, text) {
				const pad = 8;
				const maxW = Math.min(360, window.innerWidth - 2 * pad);
				const maxH = 120;
				const x = Math.max(pad, Math.min(window.innerWidth - pad - maxW, ev.clientX + 12));
				const y = Math.max(pad, Math.min(window.innerHeight - pad - maxH, ev.clientY + 12));
				tip.textContent = text;
				tip.style.left = x + "px";
				tip.style.top = y + "px";
				tip.style.display = "block";
			}
			function hideTip() { tip.style.display = "none"; }

			function onPointerMove(ev) {
				try {
					// Suppress root tooltip if another tooltip is visible
					const otherTip = document.getElementById('tooltip');
					if (otherTip && getComputedStyle(otherTip).display !== 'none') { hideTip(); return; }

					// Suppress if pointer is over a non-root node (let inner node tooltips win)
					const topEl = document.elementFromPoint(ev.clientX, ev.clientY);
					if (topEl) {
						let anc = topEl;
						while (anc && anc !== document.documentElement) {
							if (anc.classList && anc.classList.contains && anc.classList.contains('node')) break;
							anc = anc.parentNode;
						}
						if (anc && anc !== document.documentElement && anc.__data__ && anc.__data__.depth !== 0) { hideTip(); return; }
					}

					const bbox = getVisualCircleBBox();
					if (!bbox) { hideTip(); return; }

					const cx = bbox.left + bbox.width / 2;
					const cy = bbox.top + bbox.height / 2;
					const r = Math.max(bbox.width, bbox.height) / 2;

					const dx = ev.clientX - cx;
					const dy = ev.clientY - cy;
					const dist = Math.hypot(dx, dy);

					if (dist <= r) {
						// inside the visible large circle -> show root tooltip
						// use computeRootAndView() (already defined earlier in this IIFE) to avoid re-querying the DOM
						const cr = computeRootAndView();
						const n = cr && cr.rootData ? (cr.rootData.value || 0) : 0;
						showTipAt(ev, n + (n === 1 ? ' isolate' : ' isolates'));
					} else {
						hideTip();
					}
				} catch (err) {
					console.warn('LINvis: onPointerMove error', err && err.message);
					hideTip();
				}
			}



			function onPointerLeave() { hideTip(); }

			// idempotent attach / replace previous handlers
			svgNode.removeEventListener("pointermove", svgNode._linvis_root_move || (() => { }));
			svgNode.removeEventListener("pointerleave", svgNode._linvis_root_leave || (() => { }));
			svgNode._linvis_root_move = onPointerMove;
			svgNode._linvis_root_leave = onPointerLeave;
			svgNode.addEventListener("pointermove", onPointerMove, { passive: true });
			svgNode.addEventListener("pointerleave", onPointerLeave);

			console.log("LINvis: root tooltip fallback attached (no global root/view dependency).");
		} catch (e) {
			console.warn("LINvis: attachRootTooltipNoGlobals failed", e);
		}
	})();



	// ----- CLEAN TOOLTIP HANDLER -----

	// ---------- Robust fixed-size HTML tooltip (replace existing tooltip creation) ----------
	let tooltipEl = d3.select("#tooltip");
	if (tooltipEl.empty()) {
		tooltipEl = d3.select("body").append("div").attr("id", "tooltip");
	}
	tooltipEl
		.style("position", "fixed")
		.style("pointer-events", "none")
		.style("z-index", 2147483647)           // top-most
		.style("background", "rgba(0,0,0,0.85)")
		.style("color", "#fff")
		.style("padding", "6px 8px")
		.style("border-radius", "4px")
		.style("font-family", "sans-serif")
		.style("font-size", "12px")            // FIXED size in px  will not scale
		.style("line-height", "1.2")
		.style("display", "none")
		.style("max-width", "36em")
		.style("white-space", "pre-wrap")
		.style("transform", "none")            // prevent any inherited transforms
		.style("transform-origin", "0 0")
		.style("-webkit-font-smoothing", "antialiased")
		.style("box-sizing", "border-box");

	// Attach handlers directly to node groups
	node
		.on("mouseover", function(event, d) {
			tooltipEl.style("display", "block");

			if (d.depth === 0) {
				const n = d.value || 0;
				tooltipEl.text(n + (n === 1 ? " isolate" : " isolates"));
			} else {
				tooltipEl.text((d.data && d.data.name ? d.data.name : "") + " (" + (d.value || 0) + ")");

			}

			tooltipEl
				.style("left", (event.clientX + 12) + "px")
				.style("top", (event.clientY + 12) + "px");
		})
		.on("mousemove", function(event) {
			tooltipEl
				.style("left", (event.clientX + 12) + "px")
				.style("top", (event.clientY + 12) + "px");
		})
		.on("mouseout", function() {
			tooltipEl.style("display", "none");
		});

	node.append("circle")
		.attr("r", d => d.r)
		.attr("fill", d => d.children ? "#e7eef8" : "#fff")
		.attr("stroke", "#666")
		.style("stroke-width", "1px");

	// Cache circle DOM element for each node group to avoid repeated querySelector in zoomTo()
	node.each(function(d) { d.__circle = this.querySelector('circle'); });

	// Labels (per-node), start hidden
	const labels = labelLayer.selectAll("text.lbl")
		.data(nodes)
		.join("text")
		.attr("class", d => "lbl depth-" + d.depth)
		.style("pointer-events", "none")
		.style("fill", "#111")
		.style("font-weight", "600")
		.style("opacity", 0)
		.each(function(d) { d3.select(this).text(d.data.name || ""); })
		.each(function(d) { d.__label_element = this; });

	// Ensure node groups can receive pointer events even if their circles are hollow
	node.style("pointer-events", "all");


	// initial view (root)
	let view = [root.x, root.y, root.r * 2];
	labelDepth = Math.min(initialLabelDepth, maxDepth);

	// Interpolator helper
	function interpolateZoom(v0, v1) {
		const ux0 = v0[0], uy0 = v0[1], uw0 = v0[2];
		const ux1 = v1[0], uy1 = v1[1], uw1 = v1[2];
		const dx = ux1 - ux0, dy = uy1 - uy0, dw = uw1 / uw0;
		return t => {
			const x = ux0 + dx * t;
			const y = uy0 + dy * t;
			const w = uw0 * Math.pow(dw, t);
			return [x, y, w];
		};
	}

	// Wheel zoom around cursor
	svgNode.addEventListener('wheel', function(ev) {
		ev.preventDefault();
		const delta = ev.deltaY;
		const zoomFactor = Math.pow(1.0015, delta);
		const [cx, cy] = clientToData(ev.clientX, ev.clientY, view);
		const MAX_VIEW_W = root.r * 4; // prevent zooming out beyond full root extent
		const newW = Math.min(MAX_VIEW_W, view[2] * zoomFactor);
		const kNew = diameter / newW;
		const svgRect = svgRectCache;
		const newX = cx - (ev.clientX - svgRect.left - ((width - diameter) / 2) - diameter / 2) / kNew;
		const newY = cy - (ev.clientY - svgRect.top - ((height - diameter) / 2) - diameter / 2) / kNew;
		view = [newX, newY, newW];
		zoomTo(view);
	}, { passive: false });

	// Drag panning
	let dragging = false;
	let dragStart = null;
	// consolidated pointerdown: begin drag *and* register pointer for pinch gestures
	let lastPinchDist = null; // local pinch state
	svgNode.addEventListener('pointerdown', function(ev) {
		// register pointer for multi-pointer gestures
		pointers.set(ev.pointerId, ev);

		// handle mouse/pen/primary-button drag start
		if (ev.button !== 0 && ev.pointerType === 'mouse') return;
		dragging = true;
		try { svgNode.setPointerCapture(ev.pointerId); } catch (e) { /* ignore */ }
		dragStart = { clientX: ev.clientX, clientY: ev.clientY, view: view.slice() };
	});
	svgNode.addEventListener('pointermove', function(ev) {
		if (!dragging || !dragStart) return;
		ev.preventDefault();
		// compute how many px pointer moved relative to dragStart and convert to scale move
		const dx = ev.clientX - dragStart.clientX;
		const dy = ev.clientY - dragStart.clientY;
		const k = diameter / dragStart.view[2];
		const newX = dragStart.view[0] - dx / k;
		const newY = dragStart.view[1] - dy / k;
		view = [newX, newY, dragStart.view[2]];
		zoomTo(view);
	});
	svgNode.addEventListener('pointerup', function(ev) {
		if (!dragging) return;
		dragging = false;
		try { svgNode.releasePointerCapture(ev.pointerId); } catch (e) { }
		dragStart = null;
	});
	svgNode.addEventListener('pointercancel', function(ev) {
		dragging = false; dragStart = null;
	});

	// Pinch support (consolidated)
	const pointers = new Map();
	svgNode.addEventListener('pointermove', ev => {
		// update pointer record if present
		if (pointers.has(ev.pointerId)) pointers.set(ev.pointerId, ev);

		// if exactly two pointers, compute pinch factor and center then reuse helper
		if (pointers.size === 2) {
			const it = pointers.values();
			const a = it.next().value, b = it.next().value;
			const dist = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);

			if (!lastPinchDist) {
				lastPinchDist = dist;
				return;
			}
			// factor >1 => zoom out; factor <1 => zoom in (match previous behaviour)
			const factor = svg._lastPinchDist / dist;

			// center of pinch in client coordinates
			const centerX = (a.clientX + b.clientX) / 2;
			const centerY = (a.clientY + b.clientY) / 2;

			// compute and apply new view using consolidated helper
			const newView = computeViewForClientCenter(centerX, centerY, factor, view);
			view = newView;
			zoomTo(view);
			lastPinchDist = dist;
		}
	});
	svgNode.addEventListener('pointerup', ev => {
		pointers.delete(ev.pointerId);
		if (pointers.size < 2) lastPinchDist = null;
	});
	svgNode.addEventListener('pointercancel', ev => {
		pointers.delete(ev.pointerId);
		if (pointers.size < 2) lastPinchDist = null;
	});

	function zoomTo(v) {
		const t0 = performance.now();
		const k = diameter / v[2];

		// Defensive cleanup: scope removal to ringLayer (preserve persistent boundary)
		try {
			if (typeof ringLayer !== "undefined" && ringLayer) {
				ringLayer.selectAll("g.ring, circle.ring-circle, g.aggregate, circle.agg-circle, text.ring-label, text.agg-label").remove();
			} else {
				// fallback to scoped global removal if ringLayer missing
				d3.selectAll("g.ring, circle.ring-circle, g.aggregate, circle.agg-circle, text.ring-label, text.agg-label").remove();
			}
		} catch (e) {
			// ignore harmless errors
		}

		// Update node transforms and scaled radii
		node.attr("transform", d => {
			const x = (d.x - v[0]) * k + diameter / 2;
			const y = (d.y - v[1]) * k + diameter / 2;
			return `translate(${x},${y})`;
		});

		// --- visual update for nodes (conservative singleton cap & hollowing) ---
		const SINGLETON_LARGE_THRESHOLD = 16; // px  singletons above this are visually capped
		const SINGLETON_DISPLAY_CAP = 8;      // capped visual radius for very large singletons
		const HOLLOW_NODE_MAX_R = 12;         // internal nodes <= this become hollow for reduced weight
		const HOLLOW_STROKE = 0.65;
		const DEFAULT_STROKE_FACTOR = 10;

		const singletonDepths = new Set();
		nodesByDepth.forEach((arr, depth) => { if (arr && arr.length === 1) singletonDepths.add(depth); });

		node.each(function(d) {
			// true screen radius
			d._scaledR = d.r * k;

			// choose visual radius (cap only very large singletons)
			let displayR = d._scaledR;
			if (singletonDepths.has(d.depth) && d._scaledR >= SINGLETON_LARGE_THRESHOLD) {
				displayR = Math.min(displayR, SINGLETON_DISPLAY_CAP);
			}

			// stroke width
			let strokeW = Math.max(0.45, Math.min(1.0, displayR / DEFAULT_STROKE_FACTOR));

			// determine the ancestor at the colour anchor depth (colorAnchorDepth). If none (e.g. root), topAncestor stays null
			let topAncestor = null;
			if (d.depth >= colorAnchorDepth) {
				let t = d;
				while (t && t.depth > colorAnchorDepth) t = t.parent;
				if (t && t.depth === colorAnchorDepth) topAncestor = t;
			}

			// base fill/stroke decision:
			let fillColor;
			let strokeColor = "#666"; // default stroke

			if (topAncestor) {
				const key = (topAncestor.data && topAncestor.data.name) ? topAncestor.data.name : String(topAncestor.index);
				const base = top1Palette(key);
				const depthDelta = d.depth - colorAnchorDepth;
				const darkPerLevel = 0.15;
				const c = d3.color(base);
				const fillC = (depthDelta === 0) ? c : c.darker(Math.max(0, depthDelta * darkPerLevel));
				const strokeC = d3.color(fillC).darker(Math.max(0.2, Math.abs(depthDelta) * darkPerLevel * 0.6));
				fillColor = fillC && (fillC.formatHex ? fillC.formatHex() : fillC.toString());
				strokeColor = strokeC && (strokeC.formatHex ? strokeC.formatHex() : strokeC.toString());
				if (d.depth === colorAnchorDepth) strokeW = Math.max(0.9, strokeW);
			} else {
				fillColor = d.children ? "#e7eef8" : "#fff";
			}

			const exempt = (d.depth === 0) || (d.depth === maxDepth) || (d.depth === labelDepth);

			if (!exempt && d.children && displayR <= HOLLOW_NODE_MAX_R && !topAncestor) {
				fillColor = "none";
				strokeW = HOLLOW_STROKE;
			}

			if (d.depth === 0) {
				displayR = 0;
				fillColor = "none";
				strokeColor = "none";
				strokeW = 0;
			}

			// Use cached circle element and update DOM directly (faster than d3.select per node)
			const circle = d.__circle;
			if (circle) {
				// r may be fractional; keep consistent with previous behaviour
				circle.setAttribute("r", displayR);
				circle.style.strokeWidth = strokeW + "px";
				circle.setAttribute("fill", fillColor);
				circle.setAttribute("stroke", strokeColor);
			}
		});



		// ----------------- TUNED collapse & hide heuristics -----------------
		// Aggressive defaults (tweak if too/under aggressive)
		const COLLAPSE_NODE_RADIUS_PX = 12; // when avg child radius <= this, consider collapse
		const MIN_NODES_TO_COLLAPSE = 4;
		const MAX_AGGREGATES_SHOWN = 2;
		const HIDE_NODE_RADIUS_PX = 6;  // hide nodes smaller than this UNLESS exempted

		const collapsedDepths = new Set();
		const candidates = [];

		nodesByDepth.forEach((depthNodes, depth) => {
			const n = depthNodes.length;
			if (n === 0 || depth === 0 || depth === 1) {
				depthNodes.forEach(d => {
					// Use cached circle DOM element if available for faster style updates
					const c = d.__circle;
					// always show top-level groups (depth===1) and root; otherwise hide tiny items per HIDE_NODE_RADIUS_PX rule
					if (depth === 1) {
						if (c) c.style.removeProperty('opacity');
					} else if ((d._scaledR || 0) <= HIDE_NODE_RADIUS_PX && d.depth !== maxDepth && d.depth !== labelDepth) {
						if (c) c.style.opacity = '0';
					} else {
						if (c) c.style.removeProperty('opacity');
					}
				});
				return;
			}

			// If this depth has only a single node, do not collapse it  show it normally.
			if (n === 1) {
				depthNodes.forEach(d => {
					if (d.__circle) d.__circle.style.removeProperty('opacity');
				});
				return;
			}

			// For each node, hide if very small UNLESS it's on the deepest level or the selected labelDepth
			depthNodes.forEach(d => {
				const c = d.__circle;
				if ((d._scaledR || 0) <= HIDE_NODE_RADIUS_PX && d.depth !== maxDepth && d.depth !== labelDepth) {
					if (c) c.style.opacity = '0';
				} else {
					if (c) c.style.removeProperty('opacity');
				}
			});

			if (n < MIN_NODES_TO_COLLAPSE) return;

			// require same parent for safe collapse
			const p0 = depthNodes[0].parent;
			if (!p0) return;
			const sameParent = depthNodes.every(x => x.parent === p0);
			if (!sameParent) return;

			// Do not collapse the deepest level or the user-selected label depth
			if (depth === maxDepth || depth === labelDepth) return;

			const avgChildR = depthNodes.reduce((s, d) => s + (d._scaledR || 0), 0) / n;

			// Diagnostic: log depths near threshold to console (helps tuning)
			if (avgChildR <= COLLAPSE_NODE_RADIUS_PX * 1.4) {
				console.debug(`depth=${depth} n=${n} avgChildR=${avgChildR.toFixed(2)} -> consider collapse (thr=${COLLAPSE_NODE_RADIUS_PX})`);
			}

			if (avgChildR <= COLLAPSE_NODE_RADIUS_PX) {
				const parentPx = (p0.x - v[0]) * k + diameter / 2;
				const parentPy = (p0.y - v[1]) * k + diameter / 2;
				const totalVal = depthNodes.reduce((s, d) => s + (d.value || 0), 0);
				let label = (p0.data && p0.data.name) ? p0.data.name : ("level " + depth);
				if (label && label.length > 28) label = label.slice(0, 27) + "…";

				candidates.push({ depth, parent: p0, parentPx, parentPy, avgChildR, totalVal, label, n });

				// hide all child circles (we'll either show an aggregate or remain hidden)
				depthNodes.forEach(d => {
					if (d.__circle) d.__circle.style.opacity = '0';
				});
				collapsedDepths.add(depth);
			}
		});

		// update per-node label positions and visibility (single source of truth)
		labels.attr("transform", d => {
			const x = (d.x - v[0]) * k + diameter / 2;
			const y = (d.y - v[1]) * k + diameter / 2;
			return `translate(${x},${y})`;
		});

		// ===== REPLACE labels.each(...) with this faster DOM loop =====
		const labelsNodes = labels.nodes(); // cached node[] from d3 selection
		for (let i = 0; i < labelsNodes.length; i++) {
			const textEl = labelsNodes[i];           // DOM <text> element
			const d = textEl.__data__ || nodes[i];  // fallback if needed
			const scaledR = (d && d._scaledR) ? d._scaledR : (d ? d.r * k : 0);

			// default: hide
			textEl.style.removeProperty('stroke');
			textEl.style.removeProperty('stroke-width');

			if (labelDepth === 0 || collapsedDepths.has(d.depth)) {
				textEl.style.opacity = '0';
				continue;
			}

			if (d.depth === labelDepth && scaledR > 8) {
				const fontSize = Math.max(10, Math.min(14, Math.floor(scaledR / 3)));
				textEl.style.fontSize = fontSize + 'px';
				textEl.style.opacity = '1';
				textEl.style.stroke = 'rgba(255,255,255,0.95)';
				textEl.style.strokeWidth = '3px';
				textEl.style.paintOrder = 'stroke';
			} else {
				textEl.style.opacity = '0';
			}
		}

		// update the persistent boundary to match root on-screen
		try {
			const rootCx = (root.x - v[0]) * k + diameter / 2;
			const rootCy = (root.y - v[1]) * k + diameter / 2;
			const rootRpx = root.r * k;
			if (typeof boundary !== "undefined" && boundary) {
				boundary.attr("cx", rootCx).attr("cy", rootCy).attr("r", rootRpx);
			} else if (typeof ringLayer !== "undefined" && ringLayer) {
				// defensive: recreate if missing
				ringLayer.append("circle").attr("class", "boundary")
					.attr("fill", "none").attr("stroke", "#333").style("stroke-width", "1.5px")
					.attr("cx", rootCx).attr("cy", rootCy).attr("r", rootRpx).style("pointer-events", "none");
			}
		} catch (e) { /* ignore */ }
		console.debug('zoomTo ms', performance.now() - t0);
		waiting.style.display = 'none';
	}



	// Animate smooth zoom
	function smoothZoomTo(target) {
		const interp = interpolateZoom(view, target);
		const start = performance.now();
		const duration = 450;
		(function animate() {
			const t = Math.min(1, (performance.now() - start) / duration);
			const v = interp(t);
			zoomTo(v);
			if (t < 1) requestAnimationFrame(animate);
		})();
		view = target;
	}

	// Input handlers: depth changes update labels (and optionally zoom)
	function onDepthChange(event) {
		if (!depthInput) return;
		const v = parseInt(depthInput.value, 10);
		if (isNaN(v)) return;
		const bounded = Math.max(0, Math.min(v, maxDepth));
		labelDepth = bounded;
		zoomTo(view);
	}
	if (depthInput) {
		depthInput.addEventListener('input', onDepthChange);
		depthInput.addEventListener('change', onDepthChange);
	}

	// Keyboard +/- to adjust depth
	window.addEventListener('keydown', function(e) {
		if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
		if (!depthInput) return;
		if (e.key === '+' || e.key === '=') {
			depthInput.value = Math.min(maxDepth, parseInt(depthInput.value || 0, 10) + 1);
			onDepthChange();
		} else if (e.key === '-' || e.key === '_') {
			depthInput.value = Math.max(0, parseInt(depthInput.value || 0, 10) - 1);
			onDepthChange();
		}
	});

	// --- Re-centre control: attach handler ---
	(function addRecenterControl() {
		const ctrl = document.querySelector('.control');
		if (!ctrl) return;

		// reuse existing button if present, otherwise create it
		let btn = document.getElementById('linvis-recenter-btn');
		if (btn) {
			// ensure we don't attach duplicate listeners
			btn.replaceWith(btn.cloneNode(true));
			btn = document.getElementById('linvis-recenter-btn');

			btn.addEventListener('click', function() {
				try {
					// compute visible pixel height of container (same approach as fit-height)
					const contNode = container && typeof container.node === 'function' ? container.node() : null;
					let visiblePx = 0;
					if (contNode) {
						const crect = contNode.getBoundingClientRect();
						const top = Math.max(crect.top, 0);
						const bottom = Math.min(crect.bottom, window.innerHeight);
						visiblePx = Math.max(0, bottom - top);
					}
					// fallback to svg rendered height or viewBox height
					if (!visiblePx) {
						updateSvgRectCache();
						visiblePx = (svgRectCache && svgRectCache.height) ? svgRectCache.height : height;
					}

					// Keep current view width but compute v0/v1 so root's top-left aligns to pack top-left
					const targetW = view[2];
					// Convert visible pixels -> viewBox units using diameter (pack size)
					const viewBoxPerPixel = diameter / visiblePx;
					const padPx = 4;
					const padView = viewBoxPerPixel * padPx;

					const v0 = root.x - root.r + targetW / 2 + padView;
					const v1 = root.y - root.r + targetW / 2 + padView;
					const target = [v0, v1, targetW];
					// Use smooth animation only for small-to-medium datasets
					if (nodes.length < SMOOTH_ZOOM_MAX_NODES && typeof smoothZoomTo === 'function') {
						smoothZoomTo(target);
					} else {
						// for large datasets, jump directly to avoid heavy animation work
						view = target;
						zoomTo(view);
					}

				} catch (err) {
					console.warn('LINvis: anchor-top-left handler error', err && err.message);
				}
			});
		}
		// ------- Fit width (attach only if buttons exist) -------
		let fitW = document.getElementById('linvis-fit-width-btn');
		if (fitW) {
			fitW.replaceWith(fitW.cloneNode(true));
			fitW = document.getElementById('linvis-fit-width-btn');
			fitW.addEventListener('click', function() {
				const target = [root.x, root.y, root.r * 2 * (diameter / width)];
				if (nodes.length < SMOOTH_ZOOM_MAX_NODES && typeof smoothZoomTo === 'function') {
					smoothZoomTo(target);
				} else {
					view = target;
					zoomTo(view);
				}
			});
		}
		// ------- Export SVG -------
		let exportBtn = document.getElementById('linvis-export-svg-btn');
		if (exportBtn) {
			// avoid duplicate listeners by replacing node as done for other buttons
			exportBtn.replaceWith(exportBtn.cloneNode(true));
			exportBtn = document.getElementById('linvis-export-svg-btn');

			exportBtn.addEventListener('click', function() {
				try {
					// ensure any cached bounding rect is up-to-date (not strictly required for export,
					// but keeps behaviour consistent)
					if (typeof updateSvgRectCache === 'function') updateSvgRectCache();

					// Serialize the SVG DOM to a string and trigger download
					const serializer = new XMLSerializer();
					const svgString = serializer.serializeToString(svgNode);

					// compute filename: use job/key if provided, fallback to 'linvis'
					const jobKey = (typeof _linvis_key !== 'undefined' && _linvis_key) ? String(_linvis_key).split('/').pop() : null;
					const filename = (jobKey ? jobKey : 'linvis') + '.svg';

					const blob = new Blob([svgString], { type: 'image/svg+xml;charset=utf-8' });
					const url = URL.createObjectURL(blob);
					const a = document.createElement('a');
					a.href = url;
					a.download = filename;
					document.body.appendChild(a);
					a.click();
					a.remove();
					// revoke after a short time in case click hasn't started
					setTimeout(() => URL.revokeObjectURL(url), 1000);
				} catch (err) {
					console.warn('LINvis: export SVG failed', err && err.message);
				}
			});
		}
	})();

	// Initial render
	zoomTo(view);


	// Diagnostics
	console.log("LINvis: nodes:", nodes.length, "maxDepth:", maxDepth, "initial labelDepth:", labelDepth);
})();
