/*LINvis_sunburst.js
Written by Keith Jolley
Copyright (c) 2026, University of Oxford
E-mail: keith.jolley@biology.ox.ac.uk

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

Version 1.2.0.
*/

(async function() {
    const width = 960, height = 960;
    const margin = 10;
    const radius = Math.min(width, height) / 2 - margin;
    let labelDepth = 0;   // number of largest visible sectors to label
    let labelScale = 1;
    const initialLabelDepth = 0;

    let searchState = {
        mode: "id",
        matchedLeaves: new Set(),
        matchedAncestors: new Set(),
    };

    const recordIndex = {
        byId: new Map(),
        byName: new Map()
    };
    const waiting = document.getElementById('waiting');

    async function loadData() {
        const fileInput = document.getElementById("linvis-file");
        if (fileInput && fileInput.files && fileInput.files[0]) {
            const txt = await fileInput.files[0].text();
            return JSON.parse(txt);
        }

        const params = new URLSearchParams(window.location.search);
        const key = params.get("data") || params.get("job");
        if (key) {
            waiting.style.display = 'block';
            const basename = String(key).split('/').pop();
            const path = "/tmp/" + encodeURIComponent(basename) + ".json";
            const resp = await fetch(path);
            if (!resp.ok) throw new Error("HTTP " + resp.status + " when fetching " + path);
            return await resp.json();
        }

        throw new Error("No data provided (no file selected and no ?data=... URL parameter).");
    }

    const _linvis_params = new URLSearchParams(window.location.search);
    const _linvis_key = _linvis_params.get("data") || _linvis_params.get("job");
    const hasRemoteJob = Boolean(_linvis_key);

    (function toggleWrapperVisibility() {
        const wrapper = document.getElementById("linvis-file-wrapper");
        if (!wrapper) return;
        wrapper.style.display = hasRemoteJob ? "none" : "";
    })();

    let data;
    try {
        data = await loadData();
    } catch (err) {
        try { if (waiting) waiting.style.display = 'none'; } catch (e) {}
        if (!hasRemoteJob) {
            const wrapper = document.getElementById("linvis-file-wrapper");
            if (wrapper) {
                wrapper.style.display = "";
                const inp = wrapper.querySelector("#linvis-file");
                const hadFile = inp && inp.files && inp.files[0];
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
                            note.textContent = (err && err.message) ? ('Failed to parse selected JSON file: ' + err.message) : 'Failed to parse selected JSON file (invalid JSON).';
                        }
                    } catch (e) {}
                }
                if (inp && typeof inp.focus === "function") inp.focus();
            }
            return;
        }

        const el = document.getElementById("linvis_chart");
        el.textContent = hasRemoteJob && _linvis_key ? ("Failed to load data for job " + _linvis_key + ".") : "Failed to load data.";
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
        } catch (e) {}
        return;
    }

    const root = d3.hierarchy(data);
    root.eachAfter(node => {
        if (node.data && node.data.value != null) node.value = +node.data.value;
        else if (node.children) node.value = node.children.reduce((s, c) => s + (c.value || 0), 0);
        else node.value = 0;
    });

    // Keep all threshold wrapper nodes; do not collapse single-child nodes.
    void root;

    let maxDepth = 0;
    root.each(d => { if (d.depth > maxDepth) maxDepth = d.depth; });
    const radialDepth = maxDepth + 1;

    d3.partition().size([2 * Math.PI, radialDepth]).padding(0)(root);

    const nodes = root.descendants();
    nodes.forEach((node, i) => { node.id = i; });
    nodes.forEach(node => {
        if (node.children) return;
        const records = node.data && Array.isArray(node.data.records) ? node.data.records : [];
        for (const rec of records) {
            if (rec && rec.id != null) addToIndex(recordIndex.byId, String(rec.id), node);
            if (rec && rec.name) addToIndex(recordIndex.byName, String(rec.name).trim(), node);
        }
    });
    function addToIndex(map, key, node) {
        if (!key) return;
        const arr = map.get(key);
        if (arr) arr.push(node);
        else map.set(key, [node]);
    }

    const nodesByDepth = d3.group(nodes, d => d.depth);
    maxDepth = d3.max(nodes, d => d.depth);

    let colorAnchorDepth = 1;
    if ((root.children || []).length <= 1) {
        for (let d = 1;d <= Math.max(1, maxDepth);d++) {
            const arr = nodesByDepth.get(d) || [];
            if (arr.length > 1) { colorAnchorDepth = d; break; }
        }
    }

    const topKeys = (nodesByDepth.get(colorAnchorDepth) || []).map(c => (c.data && c.data.name) ? c.data.name : String(c.index));
    const top1Palette = d3.scaleOrdinal(d3.schemePastel1).domain(topKeys);

    const container = d3.select("#linvis_chart");
    if (container.empty()) {
        console.error("Container #linvis_chart not found.");
        return;
    }
    container.selectAll("*").remove();

    const svg = container.append("svg")
        .attr("viewBox", [0, 0, width, height])
        .attr("preserveAspectRatio", "xMinYMin meet")
        .attr("width", width)
        .attr("height", height)
        .style("width", width + "px")
        .style("height", height + "px")
        .style("display", "block")
        .style("touch-action", "none")
        .style("overflow", "visible");

    const bgRect = svg.append("rect")
        .attr("width", width)
        .attr("height", height)
        .attr("fill", "#fff");

    const svgNode = svg.node();
    let svgRectCache = null;
    function updateSvgRectCache() { svgRectCache = svgNode.getBoundingClientRect(); }
    window.addEventListener('resize', () => { updateSvgRectCache(); }, { passive: true });
    updateSvgRectCache();

    let panX = 0;
    let panY = 0;
    let chartScale = 1;
    const panLayer = svg.append("g").attr("class", "pan-layer");
    function applyPan() {
        panLayer.attr("transform", `translate(${panX},${panY}) scale(${chartScale})`);
    }
    applyPan();

    function nodeAtClientPoint(clientX, clientY) {
        const rect = svgRectCache || (svgNode ? svgNode.getBoundingClientRect() : null);
        if (!rect) return null;
        const cx = rect.left + rect.width / 2 + panX;
        const cy = rect.top + rect.height / 2 + panY;
        const dx = clientX - cx;
        const dy = clientY - cy;
        const angle = (Math.atan2(dy, dx) + Math.PI * 2) % (Math.PI * 2);
        const radial = (yScale && typeof yScale.invert === "function") ? yScale.invert(Math.hypot(dx, dy)) : NaN;
        const angleData = (xScale && typeof xScale.invert === "function") ? xScale.invert(angle) : NaN;
        if (!isFinite(angleData) || !isFinite(radial)) return null;
        let best = null;
        for (const d of nodes) {
            if (!d || d.depth === 0) continue;
            if (d.x0 <= angleData && angleData < d.x1 && d.y0 <= radial && radial < d.y1) {
                if (!best || d.depth > best.depth) best = d;
            }
        }
        return best;
    }

    svgNode.addEventListener('wheel', function(ev) {
        ev.preventDefault();
        updateSvgRectCache();
        const rect = svgRectCache || (svgNode ? svgNode.getBoundingClientRect() : null);
        if (!rect) return;

        const cursorX = ev.clientX - rect.left;
        const cursorY = ev.clientY - rect.top;
        const factor = Math.pow(1.0015, -ev.deltaY);
        const nextScale = Math.max(0.2, Math.min(12, chartScale * factor));

        panX = cursorX - ((cursorX - panX) / chartScale) * nextScale;
        panY = cursorY - ((cursorY - panY) / chartScale) * nextScale;
        chartScale = nextScale;
        applyPan();
    }, { passive: false });

    let draggingPan = false;
    let dragPanStart = null;
    let suppressNextClick = false;
    svgNode.addEventListener('pointerdown', function(ev) {
        if (ev.button !== 0 && ev.pointerType === 'mouse') return;
        draggingPan = true;
        dragPanStart = { x: ev.clientX, y: ev.clientY, panX, panY, scale: chartScale, pointerId: ev.pointerId };
        suppressNextClick = false;
    });
    svgNode.addEventListener('pointermove', function(ev) {
        if (!draggingPan || !dragPanStart || dragPanStart.pointerId !== ev.pointerId) return;
        ev.preventDefault();
        const dx = ev.clientX - dragPanStart.x;
        const dy = ev.clientY - dragPanStart.y;
        if (Math.abs(dx) + Math.abs(dy) > 3) suppressNextClick = true;
        panX = dragPanStart.panX + dx;
        panY = dragPanStart.panY + dy;
        chartScale = dragPanStart.scale;
        applyPan();
    });
    svgNode.addEventListener('pointerup', function(ev) {
        if (!draggingPan) return;
        draggingPan = false;
        dragPanStart = null;
    });
    svgNode.addEventListener('pointercancel', function(ev) {
        draggingPan = false;
        dragPanStart = null;
    });

    const g = panLayer.append("g").attr("transform", `translate(${width / 2},${height / 2})`);
    const arcLayer = g.append("g").attr("class", "arc-layer");
    const labelLayer = g.append("g").attr("class", "label-layer").style("pointer-events", "none");
    const centerLayer = g.append("g").attr("class", "center-layer");

    const depthInput = document.getElementById("depth");
    if (depthInput) {
        depthInput.min = 0;
        depthInput.max = 30;
        depthInput.value = Math.min(initialLabelDepth, Math.max(1, nodes.length - 1));
    }

    const selectedLabelsInput = document.getElementById("selected-labels");
    const selectedLabelsPopoutBtn = document.getElementById("selected-labels-popout");
    const selectedLabelsDetails = document.getElementById("selected-labels-details");
    let selectedLabelsDetached = false;

    const searchModeInput = document.getElementById("search-mode");
    const searchQueryInput = document.getElementById("search-query");
    const searchRunBtn = document.getElementById("search-run");
    const searchClearBtn = document.getElementById("search-clear");
    const searchResultsEl = document.getElementById("search-results");

    (function attachDepthButtons() {
        try {
            const decr = document.getElementById('depth-decr');
            const incr = document.getElementById('depth-incr');
            if (!depthInput) return;

            function stepDelta(delta) {
                const cur = parseInt(depthInput.value || 0, 10);
                const next = Math.max(0, Math.min(30, cur + delta));
                if (next !== cur) {
                    depthInput.value = next;
                    onDepthChange();
                }
            }

            if (decr) {
                decr.replaceWith(decr.cloneNode(true));
                document.getElementById('depth-decr').addEventListener('click', function() { stepDelta(-1); });
            }
            if (incr) {
                incr.replaceWith(incr.cloneNode(true));
                document.getElementById('depth-incr').addEventListener('click', function() { stepDelta(1); });
            }
        } catch (err) {
            console.warn('LINvis: attachDepthButtons failed', err && err.message);
        }
    })();

    (function attachLabelSizeButtons() {
        try {
            const decr = document.getElementById('label-size-decr');
            const incr = document.getElementById('label-size-incr');

            function stepScale(delta) {
                labelScale = Math.max(0.5, Math.min(2, Math.round((labelScale + delta) * 10) / 10));
                render();
            }

            function attachRepeat(btn, delta) {
                if (!btn) return;
                let timeoutId = null;
                let intervalId = null;
                function start() {
                    stepScale(delta);
                    timeoutId = setTimeout(() => {
                        intervalId = setInterval(() => { stepScale(delta); }, 75);
                    }, 500);
                }
                function stop() {
                    clearTimeout(timeoutId);
                    clearInterval(intervalId);
                    timeoutId = null;
                    intervalId = null;
                }
                btn.addEventListener('pointerdown', function(ev) { ev.preventDefault(); start(); });
                btn.addEventListener('pointerup', stop);
                btn.addEventListener('pointerleave', stop);
                btn.addEventListener('pointercancel', stop);
            }

            if (decr) {
                decr.replaceWith(decr.cloneNode(true));
                attachRepeat(document.getElementById('label-size-decr'), -0.1);
            }
            if (incr) {
                incr.replaceWith(incr.cloneNode(true));
                attachRepeat(document.getElementById('label-size-incr'), 0.1);
            }
        } catch (err) {
            console.warn('LINvis: attachLabelSizeButtons failed', err && err.message);
        }
    })();

    const arc = d3.arc()
        .startAngle(d => xScale(d.x0))
        .endAngle(d => xScale(d.x1))
        .innerRadius(d => yScale(d.y0))
        .outerRadius(d => Math.max(yScale(d.y0) + 1, yScale(d.y1) - 1));

    let focusNode = root;
    let xScale = d3.scaleLinear().range([0, 2 * Math.PI]);
    let yScale = d3.scaleLinear().range([0, radius]);

    function styleForNode(d) {
        let fillColor;
        let strokeColor = '#666';
        let strokeW = 1;

        let topAncestor = null;
        if (d.depth >= colorAnchorDepth) {
            let t = d;
            while (t && t.depth > colorAnchorDepth) t = t.parent;
            if (t && t.depth === colorAnchorDepth) topAncestor = t;
        }

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
            if (d.depth === colorAnchorDepth) strokeW = 1.2;
        } else {
            fillColor = d.children ? '#e7eef8' : '#fff';
        }

        if (d.depth === 0) {
            fillColor = 'none';
            strokeColor = 'none';
            strokeW = 0;
        }

        const isMatch = searchState.matchedLeaves.has(d);
        const isPath = !isMatch && searchState.matchedAncestors.has(d);
        if (isMatch) {
            strokeColor = '#d11';
            strokeW = 3;
        } else if (isPath) {
            strokeColor = '#d11';
            strokeW = 1.8;
        }

        return { fillColor, strokeColor, strokeW, isMatch, isPath };
    }

    function getSelectedLabels() {
        if (!selectedLabelsInput) return null;
        const vals = selectedLabelsInput.value.split(/\r?\n/).map(v => v.trim()).filter(Boolean);
        return vals.length ? new Set(vals) : null;
    }

    function getExactSelectedLabelForNode(d, selectedLabels) {
        if (!selectedLabels) return null;
        const names = [];
        if (d.data && d.data.name) names.push(d.data.name);
        if (d._collapsedWrapperNames && d._collapsedWrapperNames.length) names.push(...d._collapsedWrapperNames);
        let best = null;
        for (const name of names) {
            if (selectedLabels.has(name) && (!best || name.length > best.length)) best = name;
        }
        return best;
    }

    function labelScore(d) {
        const span = Math.max(0, xScale(d.x1) - xScale(d.x0));
        const midR = (yScale(d.y0) + yScale(d.y1)) / 2;
        const thickness = Math.max(1, yScale(d.y1) - yScale(d.y0));
        return span * midR * thickness;
    }

    function isAncestor(a, b) {
        for (let n = b && b.parent;n;n = n.parent) {
            if (n === a) return true;
        }
        return false;
    }

    function buildAutoLabelSet(visibleNodes, limit) {
		if (limit <= 0) return new Set();
        const ranked = visibleNodes
            .filter(d => d.depth > 0)
            .slice()
            .sort((a, b) => labelScore(b) - labelScore(a));

        const chosen = [];
        for (const d of ranked) {
            if (chosen.some(c => c === d || isAncestor(c, d) || isAncestor(d, c))) continue;
            chosen.push(d);
            if (chosen.length >= limit) break;
        }
        return new Set(chosen.map(d => d.id));
    }


    function arcVisible(d) {
        const x0 = xScale.domain()[0];
        const x1 = xScale.domain()[1];
        const y0 = yScale.domain()[0];
        const y1 = yScale.domain()[1];
        return d.depth > 0 && d.x1 > x0 && d.x0 < x1 && d.y1 > y0 && d.y0 < y1;
    }



    function labelVisible(d, exactSelectedLabel, scaledR, labelText, isAutoLabel) {
        if (!arcVisible(d)) return false;
        if (exactSelectedLabel) return true;
        if (isAutoLabel) return true;
        return false;
    }

    function labelTransform(d) {
        const angle = ((xScale(d.x0) + xScale(d.x1)) / 2) * 180 / Math.PI - 90;
        const r = (yScale(d.y0) + yScale(d.y1)) / 2;
        const flip = angle > 90 && angle < 270 ? 180 : 0;
        return `rotate(${angle}) translate(${r},0) rotate(${flip})`;
    }

    let tooltipEl = d3.select("#tooltip");
    if (tooltipEl.empty()) tooltipEl = d3.select("body").append("div").attr("id", "tooltip");
    tooltipEl
        .style("position", "fixed")
        .style("pointer-events", "none")
        .style("z-index", 2147483647)
        .style("background", "rgba(0,0,0,0.85)")
        .style("color", "#fff")
        .style("padding", "6px 8px")
        .style("border-radius", "4px")
        .style("font-family", "sans-serif")
        .style("font-size", "12px")
        .style("line-height", "1.2")
        .style("display", "none")
        .style("max-width", "36em")
        .style("white-space", "pre-wrap")
        .style("transform", "none")
        .style("transform-origin", "0 0")
        .style("box-sizing", "border-box");

    function showTooltip(event, text) {
        tooltipEl.style("display", "block").text(text);
        tooltipEl
            .style("left", (event.clientX + 12) + "px")
            .style("top", (event.clientY + 12) + "px");
    }
    function hideTooltip() { tooltipEl.style("display", "none"); }

    function render() {
        const focus = focusNode || root;
        xScale.domain([focus.x0, focus.x1]);
        yScale.domain([focus.y0, radialDepth]).range([0, radius]);

        const selectedLabels = getSelectedLabels();
        const visibleNodes = nodes.filter(arcVisible);
        const autoLabelIds = selectedLabels
            ? new Set()
            : buildAutoLabelSet(
                visibleNodes,
                Math.max(0, parseInt(depthInput ? depthInput.value : labelDepth, 10) || 0)
            );


        const slices = arcLayer.selectAll("g.slice")
            .data(visibleNodes, d => d.id);

        slices.exit().remove();

        const slicesEnter = slices.enter().append("g")
            .attr("class", "slice")
            .style("cursor", "pointer")
            .on("click", function(event, d) {
                event.stopPropagation();
                event.preventDefault();
                event.stopPropagation();
                if (event.stopImmediatePropagation) event.stopImmediatePropagation();
                if (suppressNextClick) { suppressNextClick = false; return; }
                focusNode = d;
                render();
            })
            .on("mouseover", function(event, d) {
                const text = d.depth === 0
                    ? ((d.value || 0) + ((d.value || 0) === 1 ? ' isolate' : ' isolates'))
                    : ((d.data && d.data.name ? d.data.name : '') + ' (' + (d.value || 0) + ')');
                showTooltip(event, text);
            })
            .on("mousemove", function(event) {
                if (tooltipEl.style("display") !== "none") {
                    tooltipEl.style("left", (event.clientX + 12) + "px").style("top", (event.clientY + 12) + "px");
                }
            })
            .on("mouseout", hideTooltip);

        slicesEnter.append("path");

        const merged = slicesEnter.merge(slices);
        merged.select("path")
            .attr("d", arc)
            .attr("fill", d => styleForNode(d).fillColor)
            .attr("stroke", d => styleForNode(d).strokeColor)
            .style("stroke-width", d => styleForNode(d).strokeW + "px")
            .style("stroke-dasharray", d => styleForNode(d).isMatch ? "" : (styleForNode(d).isPath ? "3 2" : ""));

        const labels = labelLayer.selectAll("text.lbl")
            .data(visibleNodes, d => d.id);

        labels.exit().remove();

        const labelsEnter = labels.enter().append("text")
            .attr("class", d => "lbl depth-" + d.depth)
            .style("pointer-events", "none")
            .style("fill", "#111")
            .style("font-weight", "600")
            .style("opacity", 0);

        labelsEnter.merge(labels)
            .attr("transform", d => labelTransform(d))
            .each(function(d) {
                const textEl = this;
                const selected = getExactSelectedLabelForNode(d, selectedLabels);
                const labelText = selected || (d.data && d.data.name ? d.data.name : "");
                const isAutoLabel = !selectedLabels && autoLabelIds.has(d.id);
                textEl.textContent = labelText;
                const isTouchDevice = window.matchMedia("(pointer: coarse)").matches;
                const baseSize = isTouchDevice ? 13 : 10;
                const maxSize = isTouchDevice ? 18 : 14;
                const scaledR = ((yScale(d.y0) + yScale(d.y1)) / 2);
                const autoSize = Math.max(baseSize, Math.min(maxSize, Math.floor(scaledR / 3)));
                const textSize = Math.max(6, Math.min(28, autoSize * labelScale));
                const visible = labelVisible(d, selected, scaledR, labelText, isAutoLabel);
                textEl.style.fontSize = textSize + 'px';
                textEl.style.opacity = visible ? '1' : '0';
                if (visible) {
                    textEl.style.stroke = 'rgba(255,255,255,0.95)';
                    textEl.style.strokeWidth = '3px';
                    textEl.style.paintOrder = 'stroke';
                } else {
                    textEl.style.removeProperty('stroke');
                    textEl.style.removeProperty('stroke-width');
                    textEl.style.removeProperty('paint-order');
                }
            });

        centerLayer.selectAll("circle.center")
            .data([focus])
            .join("circle")
            .attr("class", "center")
            .attr("r", Math.max(2, yScale(focus.y0)))
            .attr("fill", "none")
            .attr("stroke", "rgba(55, 65, 81, 0.28)")
            .style("stroke-width", "1.25px")
            .style("pointer-events", "none");

        waiting.style.display = 'none';
    }

    bgRect.on("click", function() {
        if (suppressNextClick) { suppressNextClick = false; return; }
        panX = 0;
        panY = 0;
        chartScale = 1;
        applyPan();
        focusNode = root;
        render();
    });

    function onDepthChange() {
        if (!depthInput) return;
        const v = parseInt(depthInput.value, 10);
        if (isNaN(v)) return;
        labelDepth = Math.max(0, Math.min(v, Math.max(1, nodes.length - 1)));
        render();
    }
    if (depthInput) {
        depthInput.addEventListener('input', onDepthChange);
        depthInput.addEventListener('change', onDepthChange);
        if (selectedLabelsInput) {
            selectedLabelsInput.addEventListener('input', () => {
                const hasSelectedLabels = selectedLabelsInput.value.trim().length > 0;
                if (depthInput) {
                    depthInput.disabled = hasSelectedLabels;
                    depthInput.style.opacity = hasSelectedLabels ? '0.5' : '';
                }
                render();
            });
        }
    }

    window.addEventListener('keydown', function(e) {
        if (e.target && (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA')) return;
        if (!depthInput) return;
        if (e.key === '+' || e.key === '=') {
            depthInput.value = Math.min(30, parseInt(depthInput.value || 0, 10) + 1);
            onDepthChange();
        } else if (e.key === '-' || e.key === '_') {
            depthInput.value = Math.max(0, parseInt(depthInput.value || 0, 10) - 1);
            onDepthChange();
        }
    });

    (function addSizeAndExportControls() {
        function setFixedSize(px) {
            const size = Math.max(100, Math.floor(px));
            panX = 0;
            panY = 0;
            chartScale = 1;
            applyPan();
            svg.attr("width", size).attr("height", size);
            svg.style("width", size + "px").style("height", size + "px");
            updateSvgRectCache();
            render();
        }

        let anchorBtn = document.getElementById('linvis-recenter-btn');
        if (anchorBtn) {
            anchorBtn.replaceWith(anchorBtn.cloneNode(true));
            anchorBtn = document.getElementById('linvis-recenter-btn');
            anchorBtn.addEventListener('click', function() {
                panX = 0;
                panY = 0;
                applyPan();
                const cont = container.node();
                if (cont && typeof cont.scrollTo === 'function') cont.scrollTo({ left: 0, top: 0, behavior: 'smooth' });
            });
        }

        let fitW = document.getElementById('linvis-fit-width-btn');
        if (fitW) {
            fitW.replaceWith(fitW.cloneNode(true));
            fitW = document.getElementById('linvis-fit-width-btn');
            fitW.addEventListener('click', function() {
                const rect = container.node() ? container.node().getBoundingClientRect() : null;
                const target = rect ? Math.floor(rect.width) : width;
                setFixedSize(target);
            });
        }

        let fitH = document.getElementById('linvis-fit-height-btn');
        if (fitH) {
            fitH.replaceWith(fitH.cloneNode(true));
            fitH = document.getElementById('linvis-fit-height-btn');
            fitH.addEventListener('click', function() {
                const rect = container.node() ? container.node().getBoundingClientRect() : null;
                const viewportH = window.visualViewport ? window.visualViewport.height : window.innerHeight;
                const availableH = rect ? Math.max(120, Math.floor(viewportH - rect.top - 8)) : height;
                const target = rect ? Math.min(Math.floor(rect.width), availableH) : availableH;
                setFixedSize(target);
            });
        }

        let exportBtn = document.getElementById('linvis-export-svg-btn');
        if (exportBtn) {
            exportBtn.replaceWith(exportBtn.cloneNode(true));
            exportBtn = document.getElementById('linvis-export-svg-btn');
            exportBtn.addEventListener('click', function() {
                try {
                    const serializer = new XMLSerializer();
                    const svgString = serializer.serializeToString(svgNode);
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
                    setTimeout(() => URL.revokeObjectURL(url), 1000);
                } catch (err) {
                    console.warn('LINvis: export SVG failed', err && err.message);
                }
            });
        }
    })();

    function clearSearchState() {
        searchState.matchedLeaves.clear();
        searchState.matchedAncestors.clear();
        if (searchResultsEl) searchResultsEl.textContent = "";
    }

    function renderSearchResults(nodesForResult) {
        if (!searchResultsEl) return;
        if (!nodesForResult || !nodesForResult.length) {
            searchResultsEl.textContent = "No match.";
            return;
        }
        if (nodesForResult.length === 1) {
            const d = nodesForResult[0];
            const recs = (d.data && Array.isArray(d.data.records)) ? d.data.records : [];
            const found = recs.length ? recs[0] : null;
            if (searchState.mode === "id") {
                searchResultsEl.textContent = found && found.id != null ? ("Isolate " + found.id + " found.") : "Isolate found.";
            } else {
                searchResultsEl.textContent = found && found.name ? ("Isolate " + found.name + " found.") : "Isolate found.";
            }
            return;
        }
        searchResultsEl.textContent = nodesForResult.length + (searchState.mode === "name" ? (nodesForResult.length === 1 ? " isolate found with this name." : " isolates found with this name.") : (nodesForResult.length === 1 ? " isolate found." : " isolates found."));
    }

    function runSearch() {
        const mode = searchModeInput ? searchModeInput.value : "id";
        const q = searchQueryInput ? searchQueryInput.value.trim() : "";
        clearSearchState();
        searchState.mode = mode;
        searchState.query = q;
        if (!q) {
            renderSearchResults([]);
            render();
            return;
        }
        const hits = (mode === "name" ? recordIndex.byName : recordIndex.byId).get(q) || [];
        for (const leaf of hits) {
            searchState.matchedLeaves.add(leaf);
            for (let n = leaf.parent;n;n = n.parent) searchState.matchedAncestors.add(n);
        }
        renderSearchResults(hits);
        render();
    }

    if (searchRunBtn) searchRunBtn.addEventListener('click', runSearch);
    if (searchQueryInput) searchQueryInput.addEventListener('keydown', function(ev) {
        if (ev.key === 'Enter') runSearch();
    });
    if (searchClearBtn) searchClearBtn.addEventListener('click', function() {
        if (searchQueryInput) searchQueryInput.value = '';
        clearSearchState();
        render();
    });

    (function attachSelectedLabelsPopout() {
        if (!selectedLabelsPopoutBtn || !selectedLabelsDetails) return;
        let dragState = null;
        selectedLabelsPopoutBtn.addEventListener('click', function() {
            const panel = selectedLabelsInput ? selectedLabelsInput.parentElement : null;
            if (!panel) return;
            selectedLabelsDetached = !selectedLabelsDetached;
            if (selectedLabelsDetached) {
                panel.style.position = 'fixed';
                panel.style.top = '80px';
                panel.style.left = '80px';
                panel.style.zIndex = '100000';
                panel.style.resize = 'none';
                panel.style.overflow = 'auto';
                panel.style.cursor = 'move';
                selectedLabelsPopoutBtn.textContent = 'Dock';
                panel.addEventListener('pointerdown', function(ev) {
                    if (ev.target.tagName === 'TEXTAREA' || ev.target.tagName === 'BUTTON') return;
                    dragState = { x: ev.clientX, y: ev.clientY, left: parseInt(panel.style.left || 0, 10), top: parseInt(panel.style.top || 0, 10) };
                    ev.preventDefault();
                });
                window.addEventListener('pointermove', function(ev) {
                    if (!dragState) return;
                    panel.style.left = (dragState.left + (ev.clientX - dragState.x)) + 'px';
                    panel.style.top = (dragState.top + (ev.clientY - dragState.y)) + 'px';
                });
                window.addEventListener('pointerup', function() { dragState = null; });
            } else {
                panel.style.position = 'absolute';
                panel.style.top = '100%';
                panel.style.left = '0';
                panel.style.zIndex = '1000';
                panel.style.resize = '';
                panel.style.cursor = '';
                selectedLabelsPopoutBtn.textContent = 'Pop out';
            }
        });
    })();

    render();
    console.log("LINvis: nodes:", nodes.length, "maxDepth:", maxDepth, "initial labelDepth:", labelDepth);
})();
