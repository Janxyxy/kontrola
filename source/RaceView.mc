import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

const PAGE_COUNT = 3;          // 0 main, 1 body, 2 splits
const SPLIT_POPUP_MS = 4000;   // how long the split is shown after a punch

// Course overprint colour, used for every course symbol (start, controls, finish, progress)
const ACCENT = 0xFF00FF;

// Race mode screens. Deliberately no map, position or bearing (IOF-legal).
class RaceView extends WatchUi.View {

    var page as Number = 0;
    private var _race as RaceSession;
    private var _timer as Timer.Timer;

    // set each frame
    private var _w as Number = 0;
    private var _h as Number = 0;
    private var _cx as Number = 0;
    private var _cy as Number = 0;
    private var _s as Float = 1.0;     // scale vs the 260 px FR955 layout

    function initialize(race as RaceSession) {
        View.initialize();
        _race = race;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    function nextPage(step as Number) as Void {
        page = (page + step + PAGE_COUNT) % PAGE_COUNT;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        _h = dc.getHeight();
        _cx = _w / 2;
        _cy = _h / 2;
        _s = _w / 260.0;
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        switch (_race.state) {
            case STATE_IDLE:
                drawPreStart(dc);
                return;
            case STATE_DONE:
                drawDone(dc);
                return;
        }

        drawProgressRing(dc);
        if (System.getTimer() - _race.lastPunchAt < SPLIT_POPUP_MS) {
            drawSplitPopup(dc);
            return;
        }
        drawStatus(dc);
        if (page == 0) {
            drawMain(dc);
        } else if (page == 1) {
            drawBody(dc);
        } else {
            drawSplits(dc);
        }
        drawPageDots(dc);
    }

    // --- screens ---

    private function drawPreStart(dc as Graphics.Dc) as Void {
        var gps = gpsStatus();
        var ready = _race.gpsAccuracy == Position.QUALITY_GOOD || _race.gpsAccuracy == Position.QUALITY_USABLE;

        // START button cue on the bezel (upper right)
        dc.setPenWidth(p(6));
        dc.setColor(ready ? Graphics.COLOR_GREEN : DIM_LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawArc(_cx, _cy, _cx - p(4), Graphics.ARC_COUNTER_CLOCKWISE, 18, 42);

        drawStartTriangle(dc, _cx, y(0.21), p(34));
        text(dc, _cx, y(0.38), Graphics.FONT_SMALL, "Kontrola", Graphics.COLOR_WHITE);

        // GPS: dot + label, centred as a group
        var label = "GPS " + gps[0];
        var tw = dc.getTextWidthInPixels(label, Graphics.FONT_TINY);
        var gx = _cx - (tw + p(14)) / 2;
        dc.setColor(gps[1], Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(gx + p(4), y(0.535), p(5));
        textLeft(dc, gx + p(14), y(0.535), Graphics.FONT_TINY, label, Graphics.COLOR_WHITE);

        var n = _race.numControls;
        text(dc, _cx, y(0.64), Graphics.FONT_TINY, n > 0 ? n.format("%d") + " controls" : "Controls not set", MUTED);

        text(dc, _cx, y(0.79), Graphics.FONT_XTINY, "Press START", MUTED);
        text(dc, _cx, y(0.87), Graphics.FONT_XTINY,
            dc.getTextWidthInPixels("hold UP for settings", Graphics.FONT_XTINY) <= x(0.62)
                ? "hold UP for settings" : "UP: settings", DIM_TEXT);
    }

    private function drawMain(dc as Graphics.Dc) as Void {
        drawTarget(dc, _cx, y(0.255));

        var leg = formatTime(_race.legMs());
        var hf = heroFont(dc, leg);
        var hy = y(0.475);
        text(dc, _cx, hy, hf, leg, Graphics.COLOR_WHITE);
        text(dc, _cx, below(dc, hy, hf), Graphics.FONT_XTINY, "LEG", DIM_TEXT);

        var total = formatTime(_race.timerMs());
        var sf = secondFont(dc, [total], x(0.7), dc.getFontHeight(hf));
        var ty = y(0.75);
        text(dc, _cx, ty, sf, total, MUTED);
        text(dc, _cx, below(dc, ty, sf), Graphics.FONT_XTINY, "TOTAL", DIM_TEXT);
    }

    private function drawBody(dc as Graphics.Dc) as Void {
        var hr = _race.heartRate();
        var zone = hr != null ? _race.heartRateZone(hr) : 0;

        var hrText = hr != null ? hr.format("%d") : "--";
        var hf = heroFont(dc, hrText);
        var hy = y(0.34);
        text(dc, _cx, hy, hf, hrText, zoneColor(zone));
        text(dc, _cx, below(dc, hy, hf), Graphics.FONT_XTINY,
            zone > 0 ? "BPM   Z" + zone.format("%d") : "BPM", DIM_TEXT);

        var leg = formatDist(_race.legDistanceM());
        var total = formatDist(_race.distanceM());
        var sf = secondFont(dc, [leg, total], x(0.33), dc.getFontHeight(hf));
        var vy = y(0.68);
        var sh = dc.getFontHeight(sf);
        var ly = below(dc, vy, sf);

        dc.setPenWidth(1);
        dc.setColor(DIM_LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_cx, vy - sh / 2 + p(4), _cx, ly + fh(dc, Graphics.FONT_XTINY) / 2);

        text(dc, x(0.32), vy, sf, leg, Graphics.COLOR_WHITE);
        // small screens: no room for the unit under each half
        var units = dc.getTextWidthInPixels("TOTAL KM", Graphics.FONT_XTINY) <= x(0.3);
        text(dc, x(0.32), ly, Graphics.FONT_XTINY, units ? "LEG KM" : "LEG", DIM_TEXT);
        text(dc, x(0.68), vy, sf, total, MUTED);
        text(dc, x(0.68), ly, Graphics.FONT_XTINY, units ? "TOTAL KM" : "TOTAL", DIM_TEXT);
    }

    private function drawSplits(dc as Graphics.Dc) as Void {
        var n = _race.splits.size();
        if (n == 0) {
            text(dc, _cx, _cy, Graphics.FONT_TINY, "No splits yet", MUTED);
            return;
        }
        var step = y(0.125);
        var rf = fit(dc, [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY], step, null, 0);
        // last 5, newest on top
        var rows = n < 5 ? n : 5;
        for (var i = 0; i < rows; i++) {
            var idx = n - 1 - i;
            var ry = y(0.26) + i * step;
            var newest = i == 0;
            drawControl(dc, x(0.36), ry, p(13), (idx + 1).format("%d"), newest ? ACCENT : DIM_LINE,
                newest ? Graphics.COLOR_WHITE : MUTED, Graphics.FONT_XTINY);
            textLeft(dc, x(0.47), ry, rf, formatTime(_race.splits[idx]),
                newest ? Graphics.COLOR_WHITE : MUTED);
        }
    }

    private function drawSplitPopup(dc as Graphics.Dc) as Void {
        var split = _race.lastSplitMs();
        drawControl(dc, _cx, y(0.27), p(34), _race.punched.format("%d"), ACCENT, Graphics.COLOR_WHITE,
            Graphics.FONT_MEDIUM);

        var st = split != null ? formatTime(split) : "--";
        var hf = heroFont(dc, st);
        var hy = y(0.56);
        text(dc, _cx, hy, hf, st, Graphics.COLOR_WHITE);

        var next = _race.targetLabel();
        var tiny = fh(dc, Graphics.FONT_TINY);
        var ny = hy + dc.getFontHeight(hf) / 2 + tiny / 2;
        text(dc, _cx, ny, Graphics.FONT_TINY, next.equals("F") ? "to finish" : "next " + next, MUTED);
        text(dc, _cx, ny + tiny / 2 + fh(dc, Graphics.FONT_XTINY) / 2, Graphics.FONT_XTINY, "hold UP to undo", DIM_TEXT);
    }

    private function drawDone(dc as Graphics.Dc) as Void {
        if (_race.saved) {
            dc.setPenWidth(p(4));
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(_cx, _cy, _cx - p(3));
        }
        drawFinish(dc, _cx, y(0.22), p(17));

        var total = formatTime(_race.timerMs());
        var hf = heroFont(dc, total);
        var hy = y(0.45);
        text(dc, _cx, hy, hf, total, Graphics.COLOR_WHITE);

        var tiny = fh(dc, Graphics.FONT_TINY);
        var cy = hy + dc.getFontHeight(hf) / 2 + tiny * 3 / 10;
        text(dc, _cx, cy, Graphics.FONT_TINY, _race.punched.format("%d") + " controls", MUTED);
        var sy = cy + tiny / 2 + fh(dc, Graphics.FONT_XTINY) / 2;
        text(dc, _cx, sy, Graphics.FONT_XTINY, _race.saved ? "Saved" : "Discarded",
            _race.saved ? Graphics.COLOR_GREEN : Graphics.COLOR_RED);
        text(dc, _cx, y(0.85), Graphics.FONT_XTINY, "BACK to exit", DIM_TEXT);
    }

    // --- shared pieces ---

    // Clock, or PAUSED, at the top
    private function drawStatus(dc as Graphics.Dc) as Void {
        if (_race.state == STATE_PAUSED) {
            text(dc, _cx, y(0.10), Graphics.FONT_XTINY, "PAUSED", Graphics.COLOR_YELLOW);
            return;
        }
        var t = System.getClockTime();
        var hour = t.hour;
        if (!System.getDeviceSettings().is24Hour) {
            hour = hour % 12 == 0 ? 12 : hour % 12;
        }
        text(dc, _cx, y(0.10), Graphics.FONT_XTINY, hour.format("%d") + ":" + t.min.format("%02d"), MUTED);
    }

    // Course progress around the bezel; whole ring yellow while paused
    private function drawProgressRing(dc as Graphics.Dc) as Void {
        var r = _cx - p(3);
        dc.setPenWidth(p(4));
        if (_race.state == STATE_PAUSED) {
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawCircle(_cx, _cy, r);
            return;
        }
        var total = _race.numControls;
        if (total <= 0) {
            return;
        }
        dc.setColor(DIM_LINE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(_cx, _cy, r);
        var done = _race.punched < total ? _race.punched : total;
        if (done > 0) {
            dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
            if (done == total) {
                dc.drawCircle(_cx, _cy, r);
            } else {
                var end = 90 - (360 * done / total);
                dc.drawArc(_cx, _cy, r, Graphics.ARC_CLOCKWISE, 90, end);
            }
        }
    }

    // Next control as a course symbol: circle with number (+ "/14"), or finish
    private function drawTarget(dc as Graphics.Dc, tx as Number, ty as Number) as Void {
        var label = _race.targetLabel();
        if (label.equals("F")) {
            drawFinish(dc, tx - p(34), ty, p(14));
            textLeft(dc, tx - p(12), ty, Graphics.FONT_TINY, "FINISH", Graphics.COLOR_WHITE);
            return;
        }
        var next = (_race.punched + 1).format("%d");
        if (_race.numControls > 0) {
            var of = "/" + _race.numControls.format("%d");
            drawControl(dc, tx - p(14), ty, p(19), next, ACCENT, Graphics.COLOR_WHITE, Graphics.FONT_TINY);
            textLeft(dc, tx + p(10), ty, Graphics.FONT_TINY, of, DIM_TEXT);
        } else {
            drawControl(dc, tx, ty, p(19), next, ACCENT, Graphics.COLOR_WHITE, Graphics.FONT_TINY);
        }
    }

    private function drawPageDots(dc as Graphics.Dc) as Void {
        var r = _cx - p(15);
        for (var i = 0; i < PAGE_COUNT; i++) {
            var a = Math.toRadians(180 + (i - 1) * 9);
            var px = _cx + r * Math.cos(a);
            var py = _cy - r * Math.sin(a);
            dc.setColor(i == page ? Graphics.COLOR_WHITE : DIM_LINE, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(px, py, p(3));
        }
    }

    private function drawControl(dc as Graphics.Dc, px as Number, py as Number, r as Number, label as String,
                                 ring as Graphics.ColorType, fg as Graphics.ColorType,
                                 font as Graphics.FontDefinition) as Void {
        dc.setPenWidth(r > p(20) ? p(4) : p(3));
        dc.setColor(ring, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(px, py, r);
        text(dc, px, py, font, label, fg);
    }

    private function drawStartTriangle(dc as Graphics.Dc, px as Number, py as Number, side as Number) as Void {
        var hgt = side * 0.866;
        var top = [px, py - hgt * 2 / 3];
        var left = [px - side / 2, py + hgt / 3];
        var right = [px + side / 2, py + hgt / 3];
        dc.setPenWidth(p(3));
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(top[0], top[1], left[0], left[1]);
        dc.drawLine(left[0], left[1], right[0], right[1]);
        dc.drawLine(right[0], right[1], top[0], top[1]);
    }

    private function drawFinish(dc as Graphics.Dc, px as Number, py as Number, r as Number) as Void {
        dc.setPenWidth(p(3));
        dc.setColor(ACCENT, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(px, py, r);
        dc.drawCircle(px, py, r * 2 / 3);
    }

    // --- helpers ---

    // --- fonts: pick the biggest that fits, since font sizes differ a lot between watches ---

    // Big number: at most ~31% of the screen height and 80% of its width
    private function heroFont(dc as Graphics.Dc, s as String) as Graphics.FontDefinition {
        return fit(dc, [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_LARGE,
            Graphics.FONT_NUMBER_MILD, Graphics.FONT_MEDIUM], y(0.31), s, x(0.8));
    }

    // Secondary number: at most ~19% of the screen height and 3/4 of the hero, every string within maxW
    private function secondFont(dc as Graphics.Dc, strings as Array<String>, maxW as Number,
                                heroH as Number) as Graphics.FontDefinition {
        var maxH = y(0.19) < heroH * 3 / 4 ? y(0.19) : heroH * 3 / 4;
        var fonts = [Graphics.FONT_NUMBER_MILD, Graphics.FONT_LARGE, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL,
            Graphics.FONT_TINY];
        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            if (dc.getFontHeight(f) > maxH) {
                continue;
            }
            var ok = true;
            for (var j = 0; j < strings.size(); j++) {
                if (dc.getTextWidthInPixels(strings[j], f) > maxW) {
                    ok = false;
                    break;
                }
            }
            if (ok) {
                return f;
            }
        }
        return Graphics.FONT_TINY;
    }

    // First font no taller than maxH (and, if s is given, no wider than maxW); else the last one
    private function fit(dc as Graphics.Dc, fonts as Array<Graphics.FontDefinition>, maxH as Number,
                         s as String?, maxW as Number) as Graphics.FontDefinition {
        for (var i = 0; i < fonts.size(); i++) {
            var f = fonts[i];
            if (dc.getFontHeight(f) <= maxH && (s == null || dc.getTextWidthInPixels(s, f) <= maxW)) {
                return f;
            }
        }
        return fonts[fonts.size() - 1];
    }

    // Centre y for a small label under text drawn centred at cy in font f.
    // Number fonts carry empty space below the digits; text fonts (used on small
    // screens like the FR55) don't, so the label needs a bigger gap there.
    private function below(dc as Graphics.Dc, cy as Number, f as Graphics.FontDefinition) as Number {
        var tiny = fh(dc, Graphics.FONT_XTINY);
        var number = f == Graphics.FONT_NUMBER_MILD || f == Graphics.FONT_NUMBER_MEDIUM
            || f == Graphics.FONT_NUMBER_HOT || f == Graphics.FONT_NUMBER_THAI_HOT;
        return cy + fh(dc, f) / 2 + (number ? tiny / 4 : tiny / 2);
    }

    private function fh(dc as Graphics.Dc, f as Graphics.FontDefinition) as Number {
        return dc.getFontHeight(f);
    }

    // fixed size (designed at 260 px) scaled to this screen, at least 1
    private function p(n as Number) as Number {
        var v = (n * _s + 0.5).toNumber();
        return v < 1 ? 1 : v;
    }

    private function x(f as Float) as Number {
        return (_w * f).toNumber();
    }

    private function y(f as Float) as Number {
        return (_h * f).toNumber();
    }

    private function text(dc as Graphics.Dc, px as Numeric, py as Numeric, font as Graphics.FontDefinition,
                          s as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px, py, font, s, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function textLeft(dc as Graphics.Dc, px as Numeric, py as Numeric, font as Graphics.FontDefinition,
                              s as String, color as Graphics.ColorType) as Void {
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.drawText(px, py, font, s, Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function gpsStatus() as [String, Graphics.ColorType] {
        switch (_race.gpsAccuracy) {
            case Position.QUALITY_GOOD:
                return ["ready", Graphics.COLOR_GREEN];
            case Position.QUALITY_USABLE:
                return ["ok", Graphics.COLOR_YELLOW];
            default:
                return ["searching", Graphics.COLOR_RED];
        }
    }

    private function zoneColor(zone as Number) as Graphics.ColorType {
        switch (zone) {
            case 1: return MUTED;
            case 2: return Graphics.COLOR_BLUE;
            case 3: return Graphics.COLOR_GREEN;
            case 4: return Graphics.COLOR_ORANGE;
            case 5: return Graphics.COLOR_RED;
            default: return Graphics.COLOR_WHITE;
        }
    }
}

function formatTime(ms as Number) as String {
    var s = ms / 1000;
    var hh = s / 3600;
    var mm = (s % 3600) / 60;
    var ss = s % 60;
    if (hh > 0) {
        return hh.format("%d") + ":" + mm.format("%02d") + ":" + ss.format("%02d");
    }
    return mm.format("%d") + ":" + ss.format("%02d");
}

function formatDist(m as Float) as String {
    return (m / 1000.0).format("%.2f");
}
