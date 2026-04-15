/**
 * filemanagers - Filebrowser + Syncthing control WAF
 * ES5 only (WebKit 533)
 *
 * Architecture:
 *   - Actions (start/stop/config): fire-and-forget via kindle.messaging
 *       sendStringMessage("com.kindlemodding.utild", "runCMD", cmd)
 *   - Status readback: XHR GET on file:///tmp/filemanagers.status
 *     (the WAF is served from file://, so same-origin file reads work).
 *     The shell scripts rewrite that file on every state change, and we
 *     also kick a `status` command after a toggle to refresh it.
 *
 * Status file format (two lines):
 *   fb|running|192.168.1.2:80     or  fb|stopped
 *   st|running|config|1.2.3.4:8384 or st|running|daemon|  or  st|stopped
 */

var FileManagers = (function () {
    "use strict";

    var UTILD_APP = "com.kindlemodding.utild";
    var UTILD_SEND_EVENT = "runCMD";

    var STATUS_URL = "file:///tmp/filemanagers.status";
    var FB_SCRIPT = "/mnt/us/filemanagers/filebrowser.sh";
    var ST_SCRIPT = "/mnt/us/filemanagers/syncthing.sh";
    var INSTALL_FB_SCRIPT = "/mnt/us/filemanagers/install-filebrowser.sh";
    var INSTALL_STARTUP_SCRIPT = "/mnt/us/filemanagers/install-startup.sh";

    var POLL_INTERVAL = 4000;
    var MESSAGE_TIMEOUT = 4000;

    var pollTimer = null;
    var messageTimer = null;
    var fbBusy = false;
    var stBusy = false;
    var utildOk = true;

    // ---- DOM helpers ----

    function getEl(id) { return document.getElementById(id); }

    function pressBtn(el) {
        if (typeof el === "string") el = getEl(el);
        if (el) el.className += " btn-active";
    }
    function releaseBtn(el) {
        if (typeof el === "string") el = getEl(el);
        if (el) el.className = el.className.replace(/ ?btn-active/g, "");
    }

    function escapeHtml(s) {
        if (!s) return "";
        return String(s).replace(/&/g, "&amp;")
                        .replace(/</g, "&lt;")
                        .replace(/>/g, "&gt;")
                        .replace(/"/g, "&quot;");
    }

    function showMessage(text, isError) {
        var bar = getEl("messageBar");
        bar.innerHTML = text;
        bar.className = "message-bar visible" + (isError ? " error" : "");
        if (messageTimer) clearTimeout(messageTimer);
        messageTimer = setTimeout(function () {
            bar.className = "message-bar";
        }, MESSAGE_TIMEOUT);
    }

    // ---- Utild bridge (fire-and-forget) ----

    function runCmd(cmd) {
        if (typeof kindle === "undefined" ||
            !kindle.messaging ||
            !kindle.messaging.sendStringMessage) {
            utildOk = false;
            return false;
        }
        try {
            kindle.messaging.sendStringMessage(UTILD_APP, UTILD_SEND_EVENT, cmd);
            utildOk = true;
            return true;
        } catch (e) {
            utildOk = false;
            return false;
        }
    }

    // ---- Status read (XHR on file://) ----

    function readStatus(callback) {
        // Cache-bust so the WebKit cache doesn't hand us a stale copy.
        var url = STATUS_URL + "?t=" + Date.now();
        var xhr = new XMLHttpRequest();
        var done = false;
        var timeout = setTimeout(function () {
            if (!done) { done = true; try { xhr.abort(); } catch (e) {} callback(null, "timeout"); }
        }, 3000);
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== 4 || done) return;
            done = true;
            clearTimeout(timeout);
            // file:// XHR: status is 0 on success in WebKit
            if (xhr.status === 200 || xhr.status === 0) {
                callback(xhr.responseText || "", null);
            } else {
                callback(null, "HTTP " + xhr.status);
            }
        };
        try {
            xhr.open("GET", url, true);
            xhr.send(null);
        } catch (e) {
            done = true;
            clearTimeout(timeout);
            callback(null, "xhr: " + e);
        }
    }

    // ---- Rendering ----

    function renderStopped(which) {
        var el = getEl(which === "fb" ? "statusFb" : "statusSt");
        var img = getEl(which === "fb" ? "imgFbToggle" : "imgStToggle");
        el.className = "card-status stopped";
        el.innerHTML = (which === "fb" ? "Filebrowser" : "Syncthing") + " is not running.";
        img.src = "images/toggle_off.png";
    }

    function renderFbRunning(url) {
        var el = getEl("statusFb");
        el.className = "card-status running";
        el.innerHTML = "Filebrowser is running. Access it at " +
                       '<span class="url">http://' + escapeHtml(url) + "</span>";
        getEl("imgFbToggle").src = "images/toggle_on.png";
    }

    function renderStRunning(mode, url) {
        var el = getEl("statusSt");
        el.className = "card-status running";
        if (mode === "config" && url) {
            el.innerHTML = "Syncthing is running. Configuration at " +
                           '<span class="url">http://' + escapeHtml(url) + "</span>";
        } else {
            el.innerHTML = "Syncthing daemon is running (configuration interface closed).";
        }
        getEl("imgStToggle").src = "images/toggle_on.png";
    }

    function renderNoStatusFile() {
        // No status file yet — services simply haven't been started.
        renderStopped("fb");
        renderStopped("st");
    }

    function parseStatus(text) {
        var lines = text.split("\n");
        var gotFb = false, gotSt = false;
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].split("|");
            if (parts[0] === "fb") {
                gotFb = true;
                if (parts[1] === "running") renderFbRunning(parts[2] || "");
                else renderStopped("fb");
            } else if (parts[0] === "st") {
                gotSt = true;
                if (parts[1] === "running") renderStRunning(parts[2] || "", parts[3] || "");
                else renderStopped("st");
            }
        }
        if (!gotFb) renderStopped("fb");
        if (!gotSt) renderStopped("st");
    }

    function refreshStatus() {
        readStatus(function (text, err) {
            if (err || text == null) {
                // File missing is normal before anything has run.
                renderNoStatusFile();
                return;
            }
            parseStatus(text);
        });
    }

    // Ask the scripts to (re)write the status file, then re-read it.
    function kickStatus() {
        runCmd("sh " + FB_SCRIPT + " status; sh " + ST_SCRIPT + " status");
        setTimeout(refreshStatus, 600);
        setTimeout(refreshStatus, 1800);
    }

    // ---- Actions ----

    function toggleFb() {
        if (fbBusy) return;
        fbBusy = true;
        pressBtn("btnFbToggle");
        var isOn = getEl("imgFbToggle").src.indexOf("toggle_on") !== -1;
        var action = isOn ? "stop" : "start";
        showMessage(isOn ? "Stopping Filebrowser&hellip;" : "Starting Filebrowser&hellip;", false);
        if (!runCmd("sh " + FB_SCRIPT + " " + action)) {
            showMessage("Utild not reachable", true);
            releaseBtn("btnFbToggle"); fbBusy = false;
            return;
        }
        setTimeout(function () {
            releaseBtn("btnFbToggle");
            fbBusy = false;
            refreshStatus();
        }, 2500);
    }

    function toggleSt() {
        if (stBusy) return;
        stBusy = true;
        pressBtn("btnStToggle");
        var isOn = getEl("imgStToggle").src.indexOf("toggle_on") !== -1;
        var configMode = getEl("chkStConfig").checked;
        var action;
        if (isOn) {
            action = "stop";
            showMessage("Stopping Syncthing&hellip;", false);
        } else {
            action = configMode ? "config" : "start";
            showMessage("Starting Syncthing" + (configMode ? " (config mode)" : "") + "&hellip;", false);
        }
        if (!runCmd("sh " + ST_SCRIPT + " " + action)) {
            showMessage("Utild not reachable", true);
            releaseBtn("btnStToggle"); stBusy = false;
            return;
        }
        setTimeout(function () {
            releaseBtn("btnStToggle");
            stBusy = false;
            refreshStatus();
        }, 3000);
    }

    function toggleAdvanced() {
        pressBtn("btnAdvToggle");
        setTimeout(function () { releaseBtn("btnAdvToggle"); }, 120);
        var body = getEl("advancedBody");
        var arrow = getEl("imgAdvArrow");
        if (body.className.indexOf("visible") !== -1) {
            body.className = "advanced-body";
            arrow.src = "images/arrow_down.png";
        } else {
            body.className = "advanced-body visible";
            arrow.src = "images/arrow_up.png";
        }
    }

    function runInstall(path, label, btnId) {
        pressBtn(btnId);
        showMessage(label + "&hellip;", false);
        if (!runCmd("sh " + path)) {
            showMessage("Utild not reachable", true);
            releaseBtn(btnId);
            return;
        }
        setTimeout(function () { releaseBtn(btnId); }, 400);
    }

    function quit() {
        pressBtn("btnBack");
        if (typeof kindle !== "undefined" && kindle.appmgr && kindle.appmgr.back) {
            kindle.appmgr.back();
        }
    }

    // ---- Init ----

    function bindBtn(id, fn) {
        var el = getEl(id);
        if (el) el.addEventListener("click", fn, false);
    }

    function init() {
        bindBtn("btnBack", quit);
        bindBtn("btnFbToggle", toggleFb);
        bindBtn("btnStToggle", toggleSt);
        bindBtn("btnAdvToggle", toggleAdvanced);
        bindBtn("btnInstallFb", function () {
            runInstall(INSTALL_FB_SCRIPT, "Installing filebrowser", "btnInstallFb");
        });
        bindBtn("btnInstallStartup", function () {
            runInstall(INSTALL_STARTUP_SCRIPT, "Installing startup services", "btnInstallStartup");
        });

        // First pass: try to read the status file. If missing, ask the
        // scripts to produce it so subsequent polls have something to show.
        readStatus(function (text, err) {
            if (err || text == null || text === "") {
                kickStatus();
            } else {
                parseStatus(text);
            }
        });

        pollTimer = setInterval(refreshStatus, POLL_INTERVAL);
    }

    if (document.readyState === "complete" || document.readyState === "interactive") {
        init();
    } else {
        document.addEventListener("DOMContentLoaded", init, false);
    }

    return { refresh: refreshStatus };
})();
