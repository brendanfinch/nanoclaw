# Tailscale Wedge Troubleshooting — Mac Mini M4

**Owner:** Brendan
**Target machine:** FinchBots-Mac-mini (Mac Mini M4, hostname `FinchBots-Mac-mini`, user `finchbot`)
**Tailscale install type:** App Store / standalone GUI app (`io.tailscale.ipn.macsys` variant — runs as macOS NetworkExtension, not a traditional daemon)
**Tailscale IP:** 100.116.111.23

## How to use this doc

You (the new Claude chat) are helping Brendan diagnose a Tailscale connectivity failure on his Mac Mini. He's the non-technical CEO of an edtech company — direct tone, walk through commands step-by-step, explain what each one does and why. He prefers manual approval for every command (no blanket auto-approvals).

This doc is a sibling to `screen-sharing-mac-mini.md`. A Tailscale wedge presents very similarly to a Screen Sharing failure from the user's perspective ("I can't connect to the mini") but has a completely different root cause and fix. **If the user can't reach the mini at all over Tailscale, start with this doc.** If the mini shows up online in Tailscale but Screen Sharing specifically fails, switch to the screen-sharing doc.

Start by asking him these three questions, in order, before suggesting any commands:

1. **What's the symptom?** Mini showing offline in Tailscale? Can't SSH to it? Screen Sharing fails? All of the above?
2. **Where is Brendan right now?** Sitting at the mini physically? At the MacBook only? Remote with phone access only?
3. **What did he change recently?** OS update? Tailscale app update? Reboot of the mini? Network change at the mini's location?

The second question is critical — most diagnostics for this issue require Terminal access on the mini itself. If Brendan isn't physically at the mini and Tailscale is the broken thing, remote SSH won't work either (it rides on Tailscale). Termius from iPhone via Tailscale also won't work for the same reason.

## What a Tailscale wedge actually is

The Tailscale app on the Mac Mini runs as a **NetworkExtension** (not a traditional launchd daemon). It maintains a persistent HTTPS connection to Tailscale's coordination server (controlplane.tailscale.com) to sync the "netmap" — the list of every node in the tailnet, their current IPs, and routing rules.

When that upstream connection wedges:
- The extension is still running (you'll see it in `launchctl list`)
- It still responds to local CLI calls (`tailscale status` works)
- It still has cached peer data (status shows known peers)
- BUT it can't refresh the netmap or report its own status as online
- Result: every node in the tailnet sees the mini as offline, and the mini sees its own status as stale

The key tell: a "time since last map sync" counter in `tailscale status` health warnings that doesn't advance between runs. That's a frozen daemon, not a transient network issue.

```
Mac Mini Tailscale app
   ↓ (NetworkExtension)
   ↓ HTTPS to controlplane.tailscale.com:443
   ↓ ← WEDGE LIVES HERE
   ↓
Tailscale coordination server
   ↓ pushes netmap
   ↓
All other nodes in tailnet
```

For this to work, all of the following must be true:
- Mini has working internet (general connectivity)
- DNS resolves controlplane.tailscale.com
- Outbound HTTPS (port 443) reaches Tailscale's IPs (the `192.200.0.x` range — these look weird but are normal Tailscale infrastructure)
- NetworkExtension is running AND not stuck on its upstream connection
- Tailscale auth is still valid (rarely expires unexpectedly)

## Diagnostic decision tree

### Step 1: Is the mini actually online and reachable physically?

If Brendan is physically at the mini, skip to Step 2.

If he's remote and the mini shows offline in Tailscale, his remote options are gone — SSH and Termius both ride on Tailscale. He needs to either get physical access to the mini, find someone with physical access, or wait. Don't try clever remote workarounds.

### Step 2: Confirm the wedge with `tailscale status` on the mini

```
tailscale status
```

**Looking for:**
- `finchbots-mac-mini` shows as `offline` (when it's clearly online — Brendan is staring at it)
- Health check section at the bottom showing one or both of:
  - `Tailscale hasn't received a network map from the coordination server in Xm Ys`
  - `Unable to connect to the Tailscale coordination server to synchronize the state of your tailnet`

The "time since map" counter is the killer diagnostic. Run the command twice with a 30-second gap. If the number is stuck (e.g. "2m9s" both times), the daemon is genuinely wedged — not transient network packet loss.

### Step 3: Rule out general network problems

Before assuming Tailscale is the culprit, confirm the mini's internet is fine:

```
ping -c 3 1.1.1.1
```

Cloudflare DNS, raw IP, bypasses DNS. Should return 3/3 packets at typical latency.

- **0/3 packets** → mini has no internet. Not a Tailscale problem. Check Wi-Fi/Ethernet, ISP status, physical cabling.
- **3/3 packets** → internet is fine, continue.

Then confirm DNS resolves Tailscale's coordination server:

```
nslookup controlplane.tailscale.com
```

Should return a list of IPs in `192.200.0.x`. Those IPs look weird but are normal Tailscale infrastructure — not a red flag.

Note: the `Server: 100.100.100.100` line is Tailscale's MagicDNS resolver. If that's responding, the extension is at least partially alive (it's answering local queries even though it can't talk upstream).

- **No IPs returned / timeout** → DNS issue, not Tailscale. Different troubleshooting path.
- **IPs returned** → DNS fine, Tailscale daemon is the suspect. Go to Step 4.

### Step 4: Identify Tailscale install type

```
sudo launchctl list | grep -i tailscale
```

- **Line with `io.tailscale.ipn.macsys`** → App Store / standalone GUI app (NetworkExtension). This is what Brendan has. Go to **Fix A**.
- **Line with `com.tailscale.tailscaled`** → Open source / CLI install. Go to **Fix B**.
- **No output** → Tailscale isn't running at all. Open the app from /Applications.

Confirm by checking the menubar: is there a Tailscale icon (top-right of screen)? Yes = GUI app. No = CLI install (or the app crashed entirely).

## Fixes

### Fix A: NetworkExtension wedge (App Store / GUI app — Brendan's setup)

**Don't waste time on `sudo tailscale down` + `sudo tailscale up`.** Those CLI commands talk to the NetworkExtension but can't restart it. The extension itself is what's wedged, and CLI calls won't reach the wedged part of the code.

**Correct fix: quit and relaunch the Tailscale app.** This restarts the NetworkExtension cleanly.

1. Click the Tailscale icon in the menubar → **Quit Tailscale** (usually at the bottom of the menu).
2. Verify it actually quit:
   ```
   sudo launchctl list | grep -i tailscale
   ```
   The NetworkExtension line should disappear, OR the PID should change when you relaunch. **The PID change is what matters — note the old PID before quitting so you can confirm it changed.**
3. Relaunch from `/Applications/Tailscale.app` or Spotlight (Cmd+Space → "Tailscale" → Enter). Menubar icon should reappear within ~5 seconds.
4. Wait 15 seconds for it to reconnect, then verify:
   ```
   tailscale status
   ```
   The mini should now show as `-` (no current peer connection — fine if no other node is actively talking to it) or `active`/`idle`. The health check warnings at the bottom should be **gone entirely**.

If health warnings persist after relaunch, escalate to **Fix C**.

### Fix B: tailscaled wedge (CLI install — not Brendan's current setup, included for completeness)

If a future install switches to the CLI version, kick the daemon via launchctl:

```
sudo launchctl kickstart -k system/com.tailscale.tailscaled
```

`kickstart -k` force-kills the wedged daemon and starts a fresh one. Then verify with `tailscale status`.

### Fix C: Quit/relaunch didn't work

If the NetworkExtension restarted (PID changed) but the wedge persists:

1. Check Tailscale app login state — open the app, look at the menu. If it says "Log in" or "Reconnect," auth has expired. Click through the browser flow.
2. If logged in but still wedged, check the app's "Bug Report" → "Report an issue" — sometimes the debug panel shows a more specific error than the generic "Out of Sync."
3. Last resort: reboot the mini. Per the always-on-server constraint in the screensharing handoff doc, this loses in-flight state, but if Tailscale truly won't recover, it's necessary.

## Things that have caused this in the past

### 2026-05-16 incident: NetworkExtension wedge

- **Symptom:** Mini showed offline in Tailscale; MacBook couldn't connect via Screen Sharing or SSH; opening the Tailscale app on the mini showed "Network Map Response Timeout" and "Out Of Sync" errors in the debug panel.
- **Diagnostic that nailed it:** `tailscale status` from the mini showed cached peers + a "hasn't received a network map in 2m9s" warning that didn't advance between runs. Ping to 1.1.1.1 worked (0% loss), nslookup of controlplane.tailscale.com returned IPs. So internet + DNS were fine — the daemon itself was stuck.
- **What didn't work:** `sudo tailscale down` followed by `sudo tailscale up`. CLI returned cleanly but the offline state and health warnings persisted. The CLI can't restart the NetworkExtension.
- **What worked:** Quit Tailscale from the menubar, relaunch the app. NetworkExtension PID changed from 66387 to 7666. Health warnings cleared immediately, mini came back online in the tailnet.
- **Time to diagnose and fix:** ~15 minutes.

## Don't do these things

- **Don't reboot the mini as a first move.** It's an always-on inference/agent server. Reboot wipes in-flight processes and scheduled tasks. Reboot is last resort, after fixes A through C.
- **Don't run `sudo tailscale down/up` and assume it's enough on the GUI version.** It returns cleanly even when it didn't actually fix anything. Always verify with `tailscale status` afterward — if health warnings persist, you need to restart the app, not just toggle the connection.
- **Don't log out of Tailscale to "reset" it** unless you've confirmed auth has expired. Logging out triggers the browser-based reauth flow which is friction Brendan doesn't need if the issue is just a daemon wedge.
- **Don't grant Terminal Full Disk Access to "see what's wrong."** Same security stance as the screensharing handoff — friction over broad permissions.
- **Don't change Tailscale ACLs.** ACL changes affect every node in Brendan's tailnet. A wedge on one machine is not an ACL problem.

## Tone and approach reminders

- **Verify state before acting.** "Run `tailscale status` and paste the output" not "I assume the daemon is wedged."
- **Walk through commands one at a time.** Each command gets explained, approved, and executed before the next. Explain what it does and what to expect.
- **Note PID changes as confirmation.** `launchctl list` outputs PID in the first column. Capturing it before and after a restart is the cleanest way to confirm a daemon actually cycled.
- **The `192.200.0.x` IPs in nslookup are normal.** Don't flag them as suspicious — that's just Tailscale's internal infrastructure routing.
- **When the user pastes a command and gets weird shell errors** (`zsh: command not found: finchbot@...`), it's a paste error — the prompt got included or extra newlines glued lines together. Have them retype the command fresh.

## Escalation: when to give up and try something else

If you've spent more than 30 minutes on a Tailscale wedge without progress:

1. **Reboot the mini.** Acknowledge the cost (lost in-flight state, scheduled task interruption) but it always works for stuck network extensions.
2. **After reboot, verify Tailscale auto-starts.** Run `tailscale status` and confirm it shows online before declaring victory. If it doesn't auto-start, open the Tailscale app manually and check "Launch at login" in its settings.
3. **If wedges happen more than once a month**, that's a pattern. Possible causes: Tailscale app update bug, macOS version incompatibility, something else on the mini interfering with the NetworkExtension. Document each occurrence with timestamps and what fixed it.

## Related docs

- `docs/troubleshooting/screen-sharing-mac-mini.md` — sibling doc for Screen Sharing failures. If Tailscale is healthy but Screen Sharing fails, switch to that doc and start at its Step 1.

---

End of handoff doc.
