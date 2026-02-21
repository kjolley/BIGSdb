/*LINvis.js
Written by Keith Jolley
Copyright (c) 2026, University of Oxford
E-mail: keith.jolley@biology.ox.ac.uk
*/

/*Inspired and modified from Zoomable Circle Packing 
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
*/



(async function() {
    const width = 960, height = 960;
    const diameter = Math.min(width, height) - 20;
    let labelDepth = 1;              // which depth to label
    const initialLabelDepth = 1;
    const autoZoomByDefault = false;

    // Track Shift (useful to force-zoom)
    let shiftPressed = false;
    window.addEventListener("keydown", (e) => { if (e.key === "Shift") shiftPressed = true; });
    window.addEventListener("keyup", (e) => { if (e.key === "Shift") shiftPressed = false; });

	// ---------- Flexible data loader ----------
	async function loadData(defaultPath = "./test.json") {
	  // 1) Inline JSON in page: <script id="linvis-data" type="application/json">...</script>
	  const inlineEl = document.getElementById("linvis-data");
	  if (inlineEl && inlineEl.textContent.trim().length) {
	    try {
	      return JSON.parse(inlineEl.textContent);
	    } catch (err) {
	      console.warn("LINvis: failed to parse inline JSON (#linvis-data):", err);
	      // fall through to next source
	    }
	  }

	  // 2) File input (if user has chosen a file and clicked the Load button)
	  // We check an input element with id="linvis-file" for an already selected file.
	  const fileInput = document.getElementById("linvis-file");
	  if (fileInput && fileInput.files && fileInput.files[0]) {
	    try {
	      const txt = await fileInput.files[0].text();
	      return JSON.parse(txt);
	    } catch (err) {
	      console.warn("LINvis: failed to read/parse selected file:", err);
	      // fall through
	    }
	  }

	  // 3) URL parameter: ?data=/path/to.json or ?file=/path/to.json
	  try {
	    const params = new URLSearchParams(window.location.search);
	    const url = params.get("data") || params.get("file");
	    if (url) {
	      const resp = await fetch(url);
	      if (!resp.ok) throw new Error("HTTP " + resp.status);
	      return await resp.json();
	    }
	  } catch (err) {
	    console.warn("LINvis: failed to fetch JSON from URL param:", err);
	    // fall through
	  }

	  // 4) Fallback to default path (original behaviour)
	  try {
	    const resp = await fetch(defaultPath);
	    if (!resp.ok) throw new Error("HTTP " + resp.status);
	    return await resp.json();
	  } catch (err) {
	    console.error("LINvis: failed to load default JSON (" + defaultPath + "):", err);
	    throw err; // caller will handle
	  }
	}

	// Replace original fetch usage with:
	let data;
	try {
	  data = await loadData("./test.json");
	} catch (err) {
	  const el = document.getElementById("linvis_chart");
	  if (el) el.textContent = "Failed to load data: " + (err && err.message ? err.message : err);
	  return;
	}


    // Build hierarchy, preserving explicit internal values (no double count)
    const root = d3.hierarchy(data);
    root.eachAfter(node => {
        if (node.data && node.data.value != null) node.value = +node.data.value;
        else if (node.children) node.value = node.children.reduce((s, c) => s + (c.value || 0), 0);
        else node.value = 0;
    });

    d3.pack().size([diameter, diameter]).padding(2)(root);

    // Prepare container / SVG
    const container = d3.select("#linvis_chart");
    if (container.empty()) {
        console.error("Container #linvis_chart not found.");
        return;
    }
    container.selectAll("*").remove();
    // ensure container positioned for absolute canvas
    container.style("position", "relative");
    // --- Canvas layer for fast circle rendering (minimal safe insertion) ---
    (function() {
        try {
            const canvasEl = container.append("canvas")
                .attr("class", "linvis-canvas")
                .style("position", "absolute")
                .style("left", "0")
                .style("top", "0")
                .style("width", "100%")
                .style("height", "100%")
                .style("pointer-events", "none");
            const canvasNode = canvasEl.node();
            if (canvasNode) {
                canvasNode.width = width;
                canvasNode.height = height;
            }
        } catch (e) {
            // non-fatal
            console.warn("LINvis: canvas insertion failed:", e);
        }
    })();


    const svg = container.append("svg")
        .attr("viewBox", [0, 0, width, height])
        .style("width", "100%")
        .style("height", "auto")
        .style("touch-action", "none");

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


    // Tooltip
    let tooltip = d3.select("#tooltip");
    if (tooltip.empty()) {
        tooltip = d3.select("body").append("div")
            .attr("id", "tooltip")
            .style("position", "fixed")
            .style("pointer-events", "none")
            .style("background", "rgba(0,0,0,0.85)")
            .style("color", "white")
            .style("padding", "6px 8px")
            .style("border-radius", "4px")
            .style("font", "12px sans-serif")
            .style("display", "none")
            .style("max-width", "36em")
            .style("white-space", "pre-wrap");
    }

    // Nodes + depth grouping
    const nodes = root.descendants();
    function groupByDepth(nodes) {
        const map = new Map();
        nodes.forEach(n => {
            const arr = map.get(n.depth);
            if (arr) arr.push(n); else map.set(n.depth, [n]);
        });
        return map;
    }
    const nodesByDepth = groupByDepth(nodes);
    const maxDepth = d3.max(nodes, d => d.depth);

    // Depth input + autozoom checkbox
    const depthInput = document.getElementById("depth");
    if (depthInput) {
        depthInput.min = 0;
        depthInput.max = maxDepth;
        depthInput.value = Math.min(initialLabelDepth, maxDepth);
    }
    const autoZoomCheckbox = document.getElementById("autozoom");

    // Helper: tooltip position
    function moveTooltip(event) {
        if (!tooltip.empty()) {
            tooltip.style("left", (event.clientX + 12) + "px")
                .style("top", (event.clientY + 12) + "px");
        }
    }

    // client -> data coordinates (for zoom-to-cursor)
    function clientToData(clientX, clientY, v = view) {
        const k = diameter / v[2];
        const svgRect = svg.node().getBoundingClientRect();
        const px = clientX - svgRect.left - ((width - diameter) / 2);
        const py = clientY - svgRect.top - ((height - diameter) / 2);
        const dataX = v[0] + (px - diameter / 2) / k;
        const dataY = v[1] + (py - diameter / 2) / k;
        return [dataX, dataY];
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

            // helper: compute root data/coords and view safely each pointermove
            function computeRootAndView() {
                const rootG = Array.from(document.querySelectorAll("g.node")).find(g => g && g.__data__ && g.__data__.depth === 0);
                if (!rootG) return null;
                const rootData = rootG.__data__;
                // prefer existing view if present in scope; otherwise fallback to root's own coords
                const viewNow = (typeof view !== "undefined" ? view : [rootData.x, rootData.y, rootData.r * 2]);
                return { rootData, viewNow, rootG };
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

                    // Prefer the visible persistent boundary circle (if present) for the hit test
                    let visualCircle = document.querySelector('circle.boundary');
                    // Fallback: the root group's own circle
                    if (!visualCircle) {
                        const rootG = Array.from(document.querySelectorAll('g.node')).find(g => g && g.__data__ && g.__data__.depth === 0);
                        visualCircle = rootG ? (rootG.querySelector('circle') || rootG) : null;
                    }
                    if (!visualCircle) { hideTip(); return; }

                    // Use the rendered bounding box of the chosen visual circle for hit testing
                    const bbox = visualCircle.getBoundingClientRect();
                    const cx = bbox.left + bbox.width / 2;
                    const cy = bbox.top + bbox.height / 2;
                    const r = Math.max(bbox.width, bbox.height) / 2;

                    const dx = ev.clientX - cx;
                    const dy = ev.clientY - cy;
                    const dist = Math.hypot(dx, dy);

                    if (dist <= r) {
                        // inside the visible large circle -> show root tooltip
                        // prefer reading the root data value from the root group's __data__
                        const rootG = Array.from(document.querySelectorAll('g.node')).find(g => g && g.__data__ && g.__data__.depth === 0);
                        const n = rootG && rootG.__data__ ? (rootG.__data__.value || 0) : 0;
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
            svgNode.removeEventListener("pointermove", svgNode._linvis_root_move || (() => {}));
            svgNode.removeEventListener("pointerleave", svgNode._linvis_root_leave || (() => {}));
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

    // small helper used when showing/moving tooltip
    function moveTooltipEl(event) {
        // clamp to viewport so tooltip doesn't go off-screen
        const pad = 8;
        const x = Math.max(pad, Math.min(window.innerWidth - pad - 300, event.clientX + 12));
        const y = Math.max(pad, Math.min(window.innerHeight - pad - 60, event.clientY + 12));
        tooltipEl.style("left", x + "px").style("top", y + "px");
    }


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
        .style("stroke-width", "1px")



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
    if (autoZoomByDefault && root.descendants().some(n => n.depth === labelDepth)) {
        const rep = root.descendants().find(n => n.depth === labelDepth) || root;
        view = [rep.x, rep.y, rep.r * 2];
    }
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
    svg.node().addEventListener('wheel', function(ev) {
        ev.preventDefault();
        const delta = ev.deltaY;
        const zoomFactor = Math.pow(1.0015, delta);
        const [cx, cy] = clientToData(ev.clientX, ev.clientY, view);
        const newW = view[2] * zoomFactor;
        const kNew = diameter / newW;
        const svgRect = svg.node().getBoundingClientRect();
        const newX = cx - (ev.clientX - svgRect.left - ((width - diameter) / 2) - diameter / 2) / kNew;
        const newY = cy - (ev.clientY - svgRect.top - ((height - diameter) / 2) - diameter / 2) / kNew;
        view = [newX, newY, newW];
        zoomTo(view);
    }, { passive: false });

    // Drag panning
    let dragging = false;
    let dragStart = null;
    svg.node().addEventListener('pointerdown', function(ev) {
        if (ev.button !== 0 && ev.pointerType === 'mouse') return;
        dragging = true;
        try { svg.node().setPointerCapture(ev.pointerId); } catch (e) {}
        dragStart = { clientX: ev.clientX, clientY: ev.clientY, view: view.slice() };
    });
    svg.node().addEventListener('pointermove', function(ev) {
        if (!dragging || !dragStart) return;
        ev.preventDefault();
        const dx = ev.clientX - dragStart.clientX;
        const dy = ev.clientY - dragStart.clientY;
        const k = diameter / dragStart.view[2];
        const newX = dragStart.view[0] - dx / k;
        const newY = dragStart.view[1] - dy / k;
        view = [newX, newY, dragStart.view[2]];
        zoomTo(view);
    });
    svg.node().addEventListener('pointerup', function(ev) {
        if (!dragging) return;
        dragging = false;
        try { svg.node().releasePointerCapture(ev.pointerId); } catch (e) {}
        dragStart = null;
    });
    svg.node().addEventListener('pointercancel', function(ev) {
        dragging = false; dragStart = null;
    });

    // Pinch support (rudimentary)
    const pointers = new Map();
    svg.node().addEventListener('pointerdown', ev => pointers.set(ev.pointerId, ev));
    svg.node().addEventListener('pointermove', ev => {
        if (pointers.has(ev.pointerId)) pointers.set(ev.pointerId, ev);
        if (pointers.size === 2) {
            const it = pointers.values();
            const a = it.next().value, b = it.next().value;
            const dist = Math.hypot(a.clientX - b.clientX, a.clientY - b.clientY);
            if (!svg._lastPinchDist) svg._lastPinchDist = dist;
            const factor = svg._lastPinchDist / dist;
            const centerX = (a.clientX + b.clientX) / 2;
            const centerY = (a.clientY + b.clientY) / 2;
            const [cx, cy] = clientToData(centerX, centerY, view);
            const newW = view[2] * factor;
            const kNew = diameter / newW;
            const svgRect = svg.node().getBoundingClientRect();
            const newX = cx - (centerX - svgRect.left - ((width - diameter) / 2) - diameter / 2) / kNew;
            const newY = cy - (centerY - svgRect.top - ((height - diameter) / 2) - diameter / 2) / kNew;
            view = [newX, newY, newW];
            zoomTo(view);
            svg._lastPinchDist = dist;
        }
    });
    svg.node().addEventListener('pointerup', ev => pointers.delete(ev.pointerId));
    svg.node().addEventListener('pointercancel', ev => pointers.delete(ev.pointerId));

    // ---------- zoom & label update (aggregate-bubble approach) ----------
    // Tunable thresholds
    const COLLAPSE_NODE_RADIUS_PX = 6; // avg scaled child radius (px) threshold to consider collapse
    const MIN_NODES_TO_COLLAPSE = 6;
    const MAX_AGGREGATES_SHOWN = 3;
    const AGGREGATE_RADIUS_MIN = 6;
    const AGGREGATE_RADIUS_MAX = 26;
    const AGGREGATE_FROM_AVG_MULT = 1.5;

    function zoomTo(v) {
        const k = diameter / v[2];

        // Defensive cleanup  keep persistent boundary intact
        try {
            // remove only generated aggregates / rings but preserve the boundary circle
            d3.selectAll("g.ring, circle.ring-circle, g.aggregate, circle.agg-circle, text.ring-label, text.agg-label").remove();
            // clear ringLayer content but leave boundary (if boundary exists, re-append it below)
            if (typeof ringLayer !== "undefined" && ringLayer) {
                // remove everything except the .boundary element
                ringLayer.selectAll("*:not(.boundary)").remove();
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
        // --- Palette for top-level (depth===1) nodes (insert after nodesByDepth / maxDepth) ---
        const top1Keys = (root.children || []).map(c => (c.data && c.data.name) ? c.data.name : String(c.index));
        const top1Palette = d3.scaleOrdinal(d3.schemePastel1).domain(top1Keys);


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

            // determine top-level ancestor (depth 1). If none (e.g. root), topAncestor stays null
            let topAncestor = null;
            if (d.depth >= 1) {
                let t = d;
                while (t && t.depth > 1) t = t.parent;
                if (t && t.depth === 1) topAncestor = t;
            }

            // base fill/stroke decision:
            let fillColor;
            let strokeColor = "#666"; // default stroke

            if (topAncestor) {
                // categorical base colour for this top-level group
                const key = (topAncestor.data && topAncestor.data.name) ? topAncestor.data.name : String(topAncestor.index);
                const base = top1Palette(key); // string like "#xxxxxx"

                // how far below the top node are we?
                const depthDelta = d.depth - 1; // 0 for top-level node, 1 for its children, etc.

                // darkening factor per level (tune 0.45..0.9)
                const darkPerLevel = 0.15;

                // compute derived fill & stroke using d3.color
                const c = d3.color(base);
                // if depthDelta is 0 (top-level) use base; otherwise darken progressively
                const fillC = (depthDelta === 0) ? c : c.darker(depthDelta * darkPerLevel);
                // stroke slightly darker than fill for contrast
                const strokeC = d3.color(fillC).darker(Math.max(0.2, depthDelta * darkPerLevel * 0.6));

                fillColor = fillC.formatHex ? fillC.formatHex() : fillC.toString();
                strokeColor = strokeC.formatHex ? strokeC.formatHex() : strokeC.toString();

                // ensure top-level nodes get a stronger stroke
                if (d.depth === 1) strokeW = Math.max(0.9, strokeW);
            } else {
                // fallback (root or weird case)
                fillColor = d.children ? "#e7eef8" : "#fff";
            }

            // exemptions: always show filled for root, deepest and explicitly selected depth
            const exempt = (d.depth === 0) || (d.depth === maxDepth) || (d.depth === labelDepth);

            // make internal nodes hollow (less visual weight) unless exempt or part of top-level visual colouring
            if (!exempt && d.children && displayR <= HOLLOW_NODE_MAX_R && !topAncestor) {
                fillColor = "none";
                strokeW = HOLLOW_STROKE;
            }

            // apply visual radius & style
            const circle = d3.select(this).select("circle");
            circle.attr("r", displayR)
                .style("stroke-width", strokeW + "px")
                .attr("fill", fillColor)
                .attr("stroke", strokeColor);
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
            if (n === 0 || depth === 0) {
                depthNodes.forEach(d => {
                    if ((d._scaledR || 0) <= HIDE_NODE_RADIUS_PX && d.depth !== maxDepth && d.depth !== labelDepth) {
                        d3.select(d.__node_group).select("circle").style("opacity", 0);
                    } else {
                        d3.select(d.__node_group).select("circle").style("opacity", null);
                    }
                });
                return;
            }

            // If this depth has only a single node, do not collapse it  show it normally.
            if (n === 1) {
                depthNodes.forEach(d => {
                    // ensure visible (unless intentionally tiny but still exempt singletons)
                    d3.select(d.__node_group).select("circle").style("opacity", null);
                });
                return;
            }

            // For each node, hide if very small UNLESS it's on the deepest level or the selected labelDepth
            depthNodes.forEach(d => {
                if ((d._scaledR || 0) <= HIDE_NODE_RADIUS_PX && d.depth !== maxDepth && d.depth !== labelDepth) {
                    d3.select(d.__node_group).select("circle").style("opacity", 0);
                } else {
                    d3.select(d.__node_group).select("circle").style("opacity", null);
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
                depthNodes.forEach(d => { d3.select(d.__node_group).select("circle").style("opacity", 0); });
                collapsedDepths.add(depth);
            }
        });

        // update per-node label positions and visibility (single source of truth)
        labels.attr("transform", d => {
            const x = (d.x - v[0]) * k + diameter / 2;
            const y = (d.y - v[1]) * k + diameter / 2;
            return `translate(${x},${y})`;
        });

        labels.each(function(d) {
            const el = d3.select(this);
            const scaledR = d._scaledR || d.r * k;

            if (labelDepth === 0) { el.style("opacity", 0).style("stroke", null).style("stroke-width", null); return; }
            if (collapsedDepths.has(d.depth)) { el.style("opacity", 0).style("stroke", null).style("stroke-width", null); return; }

            if (d.depth === labelDepth && scaledR > 8) {
                const fontSize = Math.max(10, Math.min(14, Math.floor(scaledR / 3)));
                el.style("font-size", fontSize + "px").style("opacity", 1).style("stroke", "rgba(255,255,255,0.95)")
                    .style("stroke-width", "3px").style("paint-order", "stroke");
            } else {
                el.style("opacity", 0).style("stroke", null).style("stroke-width", null);
            }
        });

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
        const wantZoom = (autoZoomCheckbox && autoZoomCheckbox.checked) || Boolean(event && event.shiftKey) || shiftPressed;
        if (wantZoom) {
            if (labelDepth === 0) smoothZoomTo([root.x, root.y, root.r * 2]);
            else {
                const rep = root.descendants().find(n => n.depth === labelDepth) || root;
                smoothZoomTo([rep.x, rep.y, rep.r * 2]);
            }
        } else {
            zoomTo(view);
        }
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
            onDepthChange({ shiftKey: e.shiftKey });
        } else if (e.key === '-' || e.key === '_') {
            depthInput.value = Math.max(0, parseInt(depthInput.value || 0, 10) - 1);
            onDepthChange({ shiftKey: e.shiftKey });
        }
    });

    // Initial render
    zoomTo(view);

    // Diagnostics
    console.log("LINvis: nodes:", nodes.length, "maxDepth:", maxDepth, "initial labelDepth:", labelDepth);
})();
