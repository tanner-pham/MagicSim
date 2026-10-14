# M0 Foundation + M1 Forge Headless Spike — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A working monorepo skeleton with green CI (M0), and a Java bridge that boots Forge headless, plays a seeded 4-player Commander game to completion with one scripted human seat driven through `ProtocolGuiGame` + our `IRemote`, streaming NDJSON (M1).

**Architecture:** See `ARCHITECTURE.md` ("The Forge seam"). Forge is a pinned submodule installed to the local Maven repo by `scripts/setup.sh`. The bridge depends on `forge:forge-gui:2.0.16-SNAPSHOT`. JS packages run TypeScript directly on Node 24 (type stripping), so there is no build step for `server` or `packages/protocol`.

**Tech Stack:** Java 17 target (JDK 21 OK), Maven 3.9.11 (`.tools/`), JUnit 5, Gson (already on Forge's classpath); Node 24, pnpm, TypeScript strict, zod, vitest, ESLint (typescript-eslint); Expo SDK 58.

**Verified facts this plan relies on** (checked against Forge `e8ca48dd`):
- Boot: `GuiBase.setInterface(IGuiBase)` then `FModel.initialize(IProgressBar, Function<ForgePreferences, Void>)` (pass `null, null`).
- A ready-made headless `IGuiBase` exists at `forge/forge-gui/tools/java/ForgeMatrixWriter.java` (`HeadlessGui`).
- Decks: `forge.deck.io.DeckSerializer.fromFile(File)`; `RegisteredPlayer.forCommander(Deck)`.
- Players: `GamePlayerUtil.createAiPlayer(String name, int avatarIndex)`; `new LobbyPlayerHuman(String name)`.
- `new Match(GameRules, List<RegisteredPlayer>, String)`, `match.createGame()`, `match.startGame(game)` **blocks until the game ends** and fires `GameEventGameFinished`.
- `game.subscribeToEvents(Object)` registers a Guava EventBus subscriber; `game.getOutcome().getWinningLobbyPlayer()`, `getLastTurnNumber()`, `isDraw()`.
- `HostedMatch.startMatch(GameRules, Set<GameType>, List<RegisteredPlayer>, Map<RegisteredPlayer, IGuiGame>, MusicPlaylist)` attaches GUIs to `PlayerControllerHuman` seats.
- `new ProtocolGuiGame(IRemote)`; `IRemote { void send(NetEvent); Object sendAndWait(IdentifiableNetEvent); }`; events are `GuiGameEvent` with `getMethod()` (`ProtocolMethod`) and `getObjects()`.
- `PlayerControllerHuman` implements `IGameController` (`selectButtonOk()`, `selectButtonCancel()`, `selectCard(CardView, List<CardView>, ITriggerEvent)`); `getInputProxy().getInput()` returns the active `Input`.
- Seeding: `forge.util.MyRandom.setRandom(new Random(seed))`.
- Reference decks (each exactly 100 cards): `forge/forge-gui/res/quest/commanderprecons/{Arcane Wizardry [C17] [2017],Breed Lethality [C16] [2016],Adaptive Enchantment [C18] [2018],Counter Blitz [FIC] [2025]}.dck`.

**Spike-verified (2026-10-13):** the Java in Tasks 5 and 7–12 was compiled and run against Forge `e8ca48dd` in a throwaway project before this plan was committed: 6/6 tests passed on two consecutive full runs, and the shaded jar printed `ready` then `gameOver`. Things the spike found, which the code below already handles:
- Forge uses CI-friendly versions (`${revision}`); a plain `mvn install` leaves that placeholder in the installed POMs and the bridge cannot resolve `forge-gui`. `scripts/setup.sh` installs with `flatten-maven-plugin` (`resolveCiFriendliesOnly`) so the installed POMs carry real versions. `-Drevision=` on the bridge build does not work.
- Forge AI can spend many CPU-minutes per decision on crowded boards (observed: 15+ minutes inside `AiBlockController` with the Counter Blitz deck), and JUnit's `@Timeout` cannot stop it because Forge swallows interrupts. All games take a `turnLimit` and end as a draw past it (`TurnCap`), and surefire has a hard fork timeout.
- A forced draw marks every surviving player as having won, so `report` only names a winner when the end reason is not `Draw`.
- Seeding works: two seeded games in one JVM produce identical event streams once card ids are normalized (ids come from a JVM-wide counter).
- `ForgeMatrixWriter`'s `HeadlessGui` claims every thread is the GUI thread. That is fine for all-AI games, but a human seat blocks on inputs and Forge asserts that never happens on the GUI thread, so `HeadlessGuiBase` runs a real single-thread "EDT".
- `HostedMatch.setStartGameHook` runs at turn 1, after the starting-player and mulligan prompts. `runWithHumanSeat` attaches to the game on the seat's first GUI call (`setGameView`, sent before the game thread starts) instead.
- "Who starts?" is an `InputSelectEntitiesFromList<Player>`; players are not sent through `setSelectables`, so the scripted client selects its own player for it.

---

## File structure

```
package.json, pnpm-workspace.yaml, tsconfig.base.json, eslint.config.mjs   (M0 T1)
packages/protocol/{package.json,tsconfig.json,src/index.ts,src/index.test.ts}   (M0 T2)
server/{package.json,tsconfig.json,src/http.ts,src/main.ts,src/http.test.ts}    (M0 T3)
app/  (create-expo-app output + scripts)                                        (M0 T4)
bridge/pom.xml
bridge/src/main/java/magicsim/bridge/
  HeadlessGuiBase.java    headless IGuiBase (adapted from Forge's ForgeMatrixWriter)
  ForgeRuntime.java       one-time boot, deck loading, seeding
  Ndjson.java             thread-safe NDJSON writer (Gson)
  GameRunner.java         builds a 4-player Commander match (AI or human seats), runs it, reports outcome
  JsonRemote.java         IRemote: GuiGameEvent → NDJSON; sendAndWait blocks for a reply
  SeatClient.java         interface for whatever answers a human seat (scripted test client now, server later)
  Main.java               stdio entry point (M1: `startGame` command only)
bridge/src/test/java/magicsim/bridge/
  ClasspathTest.java, ForgeRuntimeTest.java, AllAiGameTest.java, ScriptedHumanGameTest.java
  ScriptedSeatClient.java
docs/STATUS.md
```

---

## M0 — Foundation

### Task 1: Root pnpm workspace

**Files:** Create `package.json`, `pnpm-workspace.yaml`, `tsconfig.base.json`, `eslint.config.mjs`

- [ ] **Step 1: Write the workspace files**

`package.json`:
```json
{
  "name": "magicsim",
  "private": true,
  "type": "module",
  "engines": { "node": ">=24" },
  "scripts": {
    "typecheck": "pnpm -r --if-present typecheck",
    "lint": "pnpm -r --if-present lint",
    "test": "pnpm -r --if-present test"
  }
}
```

`pnpm-workspace.yaml`:
```yaml
packages:
  - server
  - app
  - packages/*
```

`tsconfig.base.json`:
```json
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noEmit": true,
    "allowImportingTsExtensions": true,
    "erasableSyntaxOnly": true,
    "verbatimModuleSyntax": true,
    "skipLibCheck": true
  }
}
```

`eslint.config.mjs`:
```js
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  { ignores: ["**/node_modules/**", "app/.expo/**", "app/dist/**", "forge/**", "bridge/**", "docs/**"] },
  js.configs.recommended,
  ...tseslint.configs.strict,
  {
    rules: {
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/consistent-type-assertions": ["error", { assertionStyle: "never" }],
    },
  },
);
```

- [ ] **Step 2: Install root dev dependencies**

Run: `pnpm add -Dw typescript vitest eslint @eslint/js typescript-eslint`
Expected: `pnpm-lock.yaml` created, no errors.

- [ ] **Step 3: Commit**

```bash
git add package.json pnpm-workspace.yaml tsconfig.base.json eslint.config.mjs pnpm-lock.yaml
git commit -m "chore: add pnpm workspace with strict TypeScript and ESLint"
```

### Task 2: `packages/protocol` skeleton

**Files:** Create `packages/protocol/package.json`, `packages/protocol/tsconfig.json`, `packages/protocol/src/index.ts`, `packages/protocol/src/index.test.ts`

- [ ] **Step 1: Write the failing test** — `packages/protocol/src/index.test.ts`
```ts
import { describe, expect, it } from "vitest";
import { BridgeMessageSchema, PROTOCOL_VERSION } from "./index.ts";

describe("BridgeMessageSchema", () => {
  it("accepts a gameOver message", () => {
    const parsed = BridgeMessageSchema.parse({ type: "gameOver", winner: "Ai(2)", turns: 14, draw: false });
    expect(parsed.type).toBe("gameOver");
  });

  it("rejects an unknown message type", () => {
    expect(() => BridgeMessageSchema.parse({ type: "nope" })).toThrow();
  });

  it("exposes a protocol version", () => {
    expect(PROTOCOL_VERSION).toBe(1);
  });
});
```

`packages/protocol/package.json`:
```json
{
  "name": "@magicsim/protocol",
  "private": true,
  "type": "module",
  "exports": { ".": "./src/index.ts" },
  "scripts": {
    "typecheck": "tsc -p tsconfig.json",
    "lint": "eslint src",
    "test": "vitest run"
  }
}
```

`packages/protocol/tsconfig.json`:
```json
{ "extends": "../../tsconfig.base.json", "include": ["src"] }
```

- [ ] **Step 2: Run it to see it fail**

Run: `pnpm --filter @magicsim/protocol add zod && pnpm --filter @magicsim/protocol test`
Expected: FAIL — cannot resolve `./index.ts`.

- [ ] **Step 3: Implement** — `packages/protocol/src/index.ts`
```ts
import { z } from "zod";

export const PROTOCOL_VERSION = 1;

export const ReadySchema = z.object({ type: z.literal("ready"), forgeVersion: z.string() });

export const EventSchema = z.object({
  type: z.literal("event"),
  seq: z.number().int().nonnegative(),
  kind: z.string(),
  text: z.string(),
});

export const GameOverSchema = z.object({
  type: z.literal("gameOver"),
  winner: z.string().nullable(),
  turns: z.number().int().nonnegative(),
  draw: z.boolean(),
});

/** M1 only: an untyped Forge GUI call, replaced by typed decisions in M2. */
export const GuiCallSchema = z.object({
  type: z.literal("gui"),
  id: z.number().int().nullable(),
  method: z.string(),
  awaitsReply: z.boolean(),
  args: z.array(z.unknown()),
});

export const ErrorSchema = z.object({ type: z.literal("error"), message: z.string() });

export const BridgeMessageSchema = z.discriminatedUnion("type", [
  ReadySchema,
  EventSchema,
  GameOverSchema,
  GuiCallSchema,
  ErrorSchema,
]);

export type BridgeMessage = z.infer<typeof BridgeMessageSchema>;
```

- [ ] **Step 4: Run tests, typecheck, lint**

Run: `pnpm --filter @magicsim/protocol test && pnpm --filter @magicsim/protocol typecheck && pnpm --filter @magicsim/protocol lint`
Expected: 3 tests pass; typecheck and lint clean.

- [ ] **Step 5: Commit**

```bash
git add packages/protocol pnpm-lock.yaml
git commit -m "feat(protocol): add bridge message schemas"
```

### Task 3: `server` skeleton with `/health`

**Files:** Create `server/package.json`, `server/tsconfig.json`, `server/src/http.ts`, `server/src/main.ts`, `server/src/http.test.ts`

- [ ] **Step 1: Write the failing test** — `server/src/http.test.ts`
```ts
import { afterEach, describe, expect, it } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { createHttpServer } from "./http.ts";

let server: Server | undefined;
afterEach(() => server?.close());

function listen(s: Server): Promise<number> {
  return new Promise((resolve) => {
    s.listen(0, () => {
      const address: AddressInfo | string | null = s.address();
      resolve(typeof address === "object" && address !== null ? address.port : 0);
    });
  });
}

describe("GET /health", () => {
  it("returns ok without auth", async () => {
    server = createHttpServer();
    const port = await listen(server);
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("returns 404 for unknown routes", async () => {
    server = createHttpServer();
    const port = await listen(server);
    const res = await fetch(`http://127.0.0.1:${port}/nope`);
    expect(res.status).toBe(404);
  });
});
```

`server/package.json`:
```json
{
  "name": "@magicsim/server",
  "private": true,
  "type": "module",
  "scripts": {
    "start": "node src/main.ts",
    "typecheck": "tsc -p tsconfig.json",
    "lint": "eslint src",
    "test": "vitest run"
  },
  "dependencies": { "@magicsim/protocol": "workspace:*" }
}
```

`server/tsconfig.json`:
```json
{ "extends": "../tsconfig.base.json", "compilerOptions": { "types": ["node"] }, "include": ["src"] }
```

- [ ] **Step 2: Run to see it fail**

Run: `pnpm --filter @magicsim/server add -D @types/node && pnpm install && pnpm --filter @magicsim/server test`
Expected: FAIL — cannot resolve `./http.ts`.

- [ ] **Step 3: Implement**

`server/src/http.ts`:
```ts
import { createServer, type Server } from "node:http";

export function createHttpServer(): Server {
  return createServer((req, res) => {
    if (req.method === "GET" && req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ ok: true }));
      return;
    }
    res.writeHead(404, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "Not found" }));
  });
}
```

`server/src/main.ts`:
```ts
import { createHttpServer } from "./http.ts";

const port = Number(process.env["PORT"] ?? 8080);
createHttpServer().listen(port, () => console.log(`[server] listening on ${port}`));
```

- [ ] **Step 4: Run tests, typecheck, lint, and a live start**

Run: `pnpm --filter @magicsim/server test && pnpm --filter @magicsim/server typecheck && pnpm --filter @magicsim/server lint`
Expected: 2 tests pass; clean.
Run: `PORT=8787 node server/src/main.ts & sleep 1; curl -s localhost:8787/health; kill %1`
Expected: `{"ok":true}`

- [ ] **Step 5: Commit**

```bash
git add server pnpm-lock.yaml
git commit -m "feat(server): add http server with health route"
```

### Task 4: Expo SDK 58 app scaffold

**Files:** Create `app/` (generated), modify `app/package.json`

- [ ] **Step 1: Find the SDK 58 tag and generate**

Run: `npm view expo dist-tags`
Expected: a tag (`beta` or `next`) pointing at `58.x`. Use that tag below (shown as `beta`).
Run: `pnpm dlx create-expo-app@latest app --template default@beta --no-install`
Expected: `app/` created; `app/package.json` has `"expo": "~58.` (or `^58.0.0-…`). If not 58, stop and record BLOCKED with the dist-tags output.

- [ ] **Step 2: Add workspace scripts** — in `app/package.json` set `"name": "app"` and add to `scripts`:
```json
"typecheck": "tsc --noEmit",
"lint": "eslint .",
"test": "echo \"no app tests yet\""
```
Add `"@magicsim/protocol": "workspace:*"` to `dependencies`.

- [ ] **Step 3: Install and check**

Run: `pnpm install && pnpm --filter app typecheck && pnpm --filter app exec expo export --platform web`
Expected: typecheck clean; `app/dist/` produced.

- [ ] **Step 4: Commit**

```bash
git add app pnpm-lock.yaml
git commit -m "feat(app): scaffold Expo SDK 58 app"
```

### Task 5: `bridge/` Maven skeleton compiling against Forge

**Files:** Create `bridge/pom.xml`, `bridge/src/test/java/magicsim/bridge/ClasspathTest.java`

- [ ] **Step 1: Write the failing test**
```java
package magicsim.bridge;

import forge.gamemodes.net.ProtocolMethod;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertNotNull;

class ClasspathTest {
    @Test
    void forgeGuiIsOnTheClasspath() {
        assertNotNull(ProtocolMethod.valueOf("getChoices"));
    }
}
```

`bridge/pom.xml`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>magicsim</groupId>
  <artifactId>forge-bridge</artifactId>
  <version>0.1.0</version>

  <properties>
    <maven.compiler.release>17</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    <!-- Must match the version installed from the pinned forge/ submodule (see forge/pom.xml versionCode). -->
    <forge.version>2.0.16-SNAPSHOT</forge.version>
    <forge.gui.dir>${project.basedir}/../forge/forge-gui</forge.gui.dir>
  </properties>

  <dependencies>
    <dependency>
      <groupId>forge</groupId>
      <artifactId>forge-gui</artifactId>
      <version>${forge.version}</version>
    </dependency>
    <dependency>
      <groupId>org.junit.jupiter</groupId>
      <artifactId>junit-jupiter</artifactId>
      <version>5.11.4</version>
      <scope>test</scope>
    </dependency>
  </dependencies>

  <build>
    <finalName>forge-bridge</finalName>
    <plugins>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-surefire-plugin</artifactId>
        <version>3.5.2</version>
        <configuration>
          <systemPropertyVariables>
            <forge.gui.dir>${forge.gui.dir}</forge.gui.dir>
          </systemPropertyVariables>
          <argLine>-Xmx3g</argLine>
          <!-- Forge ignores interrupts, so @Timeout cannot stop a stuck game; this kills the fork instead. -->
          <forkedProcessTimeoutInSeconds>900</forkedProcessTimeoutInSeconds>
        </configuration>
      </plugin>
      <plugin>
        <groupId>org.apache.maven.plugins</groupId>
        <artifactId>maven-shade-plugin</artifactId>
        <version>3.6.0</version>
        <executions>
          <execution>
            <phase>package</phase>
            <goals><goal>shade</goal></goals>
            <configuration>
              <transformers>
                <transformer implementation="org.apache.maven.plugins.shade.resource.ManifestResourceTransformer">
                  <mainClass>magicsim.bridge.Main</mainClass>
                </transformer>
                <transformer implementation="org.apache.maven.plugins.shade.resource.ServicesResourceTransformer"/>
              </transformers>
            </configuration>
          </execution>
        </executions>
      </plugin>
    </plugins>
  </build>
</project>
```

- [ ] **Step 2: Run it**

Run: `.tools/apache-maven-3.9.11/bin/mvn -B -q -f bridge/pom.xml test -Dtest=ClasspathTest`
Expected: PASS (1 test). If dependency resolution fails with `forge:forge:pom:${revision}`, the Forge install was not flattened: delete `~/.m2/repository/forge` and `.tools/forge-flattened-*`, then re-run `bash scripts/setup.sh`.

- [ ] **Step 3: Commit**

```bash
git add bridge
git commit -m "feat(bridge): add Maven project compiling against Forge"
```

### Task 6: CI green + status file

**Files:** Modify `docs/STATUS.md` (it already holds the planning handoff)

- [ ] **Step 1:** Run `bash scripts/verify.sh` locally. Expected: rungs 1–2 and 3 run; all pass; final line `[verify] Passed 2 rung(s).`
- [ ] **Step 2:** Rewrite `docs/STATUS.md` using the template in `AGENTS.md` (Status: DONE, Milestone: M0).
- [ ] **Step 3:** Commit `docs: record M0 status`, push, and confirm the `ci` workflow passes: `gh run watch --exit-status`. Expected: success. **M0 gate met.**

---

## M1 — Forge headless spike

### Task 7: Headless Forge boot

**Files:** Create `bridge/src/main/java/magicsim/bridge/HeadlessGuiBase.java`, `bridge/src/main/java/magicsim/bridge/ForgeRuntime.java`, test `bridge/src/test/java/magicsim/bridge/ForgeRuntimeTest.java`

- [ ] **Step 1: Write the failing test**
```java
package magicsim.bridge;

import forge.deck.Deck;
import forge.deck.DeckSection;
import forge.model.FModel;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class ForgeRuntimeTest {
    @BeforeAll
    static void boot() {
        ForgeRuntime.boot(Path.of(System.getProperty("forge.gui.dir")));
    }

    @Test
    void loadsCardDatabase() {
        assertNotNull(FModel.getMagicDb().getCommonCards().getCard("Sol Ring"));
    }

    @Test
    void loadsAllFourReferencePrecons() {
        for (String name : ForgeRuntime.REFERENCE_PRECONS) {
            Deck deck = ForgeRuntime.loadPrecon(name);
            assertEquals(1, deck.get(DeckSection.Commander).countAll(), name);
            assertEquals(99, deck.getMain().countAll(), name);
        }
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `.tools/apache-maven-3.9.11/bin/mvn -B -q -f bridge/pom.xml test -Dtest=ForgeRuntimeTest`
Expected: FAIL — `ForgeRuntime` does not exist.

- [ ] **Step 3: Implement `HeadlessGuiBase`**: adapted from the `HeadlessGui` nested class in `forge/forge-gui/tools/java/ForgeMatrixWriter.java`, with two changes: `hostMatch()` returns a real `HostedMatch`, and the GUI thread is a real single-thread executor (see the spike notes at the top). Forge is GPL-3.0 and so is this repo; keep the attribution comment.
```java
package magicsim.bridge;

// Adapted from Forge (GPL-3.0): forge-gui/tools/java/ForgeMatrixWriter.java HeadlessGui
import forge.gui.GuiBase;
import forge.gui.download.GuiDownloadService;
import forge.gui.interfaces.IGuiBase;
import forge.gui.interfaces.IGuiGame;
import forge.item.PaperCard;
import forge.localinstance.skin.FSkinProp;
import forge.localinstance.skin.ISkinImage;
import forge.sound.IAudioClip;
import forge.sound.IAudioMusic;
import forge.util.FSerializableFunction;
import forge.util.ImageFetcher;
import forge.gamemodes.match.HostedMatch;
import org.jupnp.UpnpServiceConfiguration;
import java.io.File;
import java.io.IOException;
import java.net.URISyntaxException;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.function.Consumer;

public final class HeadlessGuiBase implements IGuiBase {
    private final String assetsDir;

    public HeadlessGuiBase(Path forgeGuiDir) {
        this.assetsDir = forgeGuiDir.toString() + File.separator;
    }

    @Override public boolean isRunningOnDesktop() { return true; }
    @Override public boolean isLibgdxPort() { return false; }
    @Override public String getCurrentVersion() { return "headless"; }
    // A human seat blocks the game thread on inputs, and Forge asserts that never happens on the GUI
    // thread, so the GUI thread must be a real, separate thread (Forge's desktop uses the Swing EDT).
    private static final ExecutorService EDT = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "forge-edt");
        t.setDaemon(true);
        EDT_THREAD = t;
        return t;
    });
    private static volatile Thread EDT_THREAD;

    @Override public void invokeInEdtNow(Runnable runnable) { runnable.run(); }
    @Override public void invokeInEdtLater(Runnable runnable) { EDT.execute(runnable); }
    @Override public void invokeInEdtAndWait(Runnable proc) {
        if (isGuiThread()) { proc.run(); return; }
        try {
            EDT.submit(proc).get();
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("[HeadlessGuiBase:invokeInEdtAndWait] Interrupted", e);
        } catch (ExecutionException e) {
            throw new IllegalStateException("[HeadlessGuiBase:invokeInEdtAndWait] GUI task failed", e.getCause());
        }
    }
    @Override public void runBackgroundTask(String message, Runnable task) { task.run(); }
    @Override public boolean isGuiThread() { return Thread.currentThread() == EDT_THREAD; }
    @Override public String getAssetsDir() { return assetsDir; }
    @Override public ImageFetcher getImageFetcher() { return null; }
    @Override public ISkinImage getSkinIcon(FSkinProp skinProp) { return null; }
    @Override public ISkinImage getUnskinnedIcon(String path) { return null; }
    @Override public ISkinImage getCardArt(PaperCard card, boolean backFace) { return null; }
    @Override public ISkinImage createLayeredImage(PaperCard card, FSkinProp background, String overlayFilename, float opacity) { return null; }
    @Override public void clearImageCache() { }
    @Override public String encodeSymbols(String str, boolean formatReminderText) { return str; }
    @Override public int getAvatarCount() { return 0; }
    @Override public int getSleevesCount() { return 0; }
    @Override public float getScreenScale() { return 1.0f; }
    @Override public void preventSystemSleep(boolean preventSleep) { }
    @Override public void download(GuiDownloadService service, Consumer<Boolean> callback) { callback.accept(false); }
    @Override public void copyToClipboard(String text) { }
    @Override public void browseToUrl(String url) throws IOException, URISyntaxException { }
    @Override public void showCardList(String title, String message, List<PaperCard> list) { }
    @Override public boolean showBoxedProduct(String title, String message, List<PaperCard> list) { return false; }
    @Override public void showBugReportDialog(String title, String text, boolean showExitAppBtn) { }
    @Override public void showImageDialog(ISkinImage image, String message, String title) { }
    @Override public int showOptionDialog(String message, String title, FSkinProp icon, List<String> options, int defaultOption) { return defaultOption; }
    @Override public String showInputDialog(String message, String title, FSkinProp icon, String initialInput, List<String> inputOptions, boolean isNumeric) { return initialInput; }
    @Override public String showFileDialog(String title, String defaultDir) { return defaultDir; }
    @Override public File getSaveFile(File defaultFile) { return defaultFile; }
    @Override public <T> List<T> order(String title, String top, int remainingObjectsMin, int remainingObjectsMax, List<T> sourceChoices, List<T> destChoices) { return destChoices; }
    @Override public <T> List<T> getChoices(String message, int min, int max, Collection<T> choices, Collection<T> selected, FSerializableFunction<T, String> display) { return new ArrayList<>(selected); }
    @Override public PaperCard chooseCard(String title, String message, List<PaperCard> list) { return list.isEmpty() ? null : list.get(0); }
    @Override public boolean isSupportedAudioFormat(File file) { return false; }
    @Override public IAudioClip createAudioClip(String filename) { return null; }
    @Override public IAudioMusic createAudioMusic(String filename) { return null; }
    @Override public void startAltSoundSystem(String filename, boolean isSynchronized) { }
    @Override public void showSpellShop() { }
    @Override public void showBazaar() { }
    @Override public IGuiGame getNewGuiGame() { return null; }
    @Override public HostedMatch hostMatch() { return new HostedMatch(); }
    @Override public UpnpServiceConfiguration getUpnpPlatformService() { return null; }
    @Override public boolean hasNetGame() { return false; }
}
```

- [ ] **Step 4: Implement `ForgeRuntime`**
```java
package magicsim.bridge;

import forge.deck.Deck;
import forge.deck.io.DeckSerializer;
import forge.gui.GuiBase;
import forge.model.FModel;
import forge.util.MyRandom;

import java.io.File;
import java.nio.file.Path;
import java.util.List;
import java.util.Random;

public final class ForgeRuntime {
    public static final List<String> REFERENCE_PRECONS = List.of(
            "Arcane Wizardry [C17] [2017]",
            "Breed Lethality [C16] [2016]",
            "Adaptive Enchantment [C18] [2018]",
            "Counter Blitz [FIC] [2025]");

    private static Path forgeGuiDir;

    private ForgeRuntime() {}

    public static synchronized void boot(Path guiDir) {
        if (forgeGuiDir != null) return;
        System.setProperty("java.awt.headless", "true");
        GuiBase.setInterface(new HeadlessGuiBase(guiDir));
        FModel.initialize(null, null);
        forgeGuiDir = guiDir;
    }

    public static Deck loadPrecon(String name) {
        File file = forgeGuiDir.resolve("res/quest/commanderprecons/" + name + ".dck").toFile();
        Deck deck = DeckSerializer.fromFile(file);
        if (deck == null) {
            throw new IllegalArgumentException("[ForgeRuntime:loadPrecon] Deck not found — " + file);
        }
        return deck;
    }

    public static void seed(long seed) {
        MyRandom.setRandom(new Random(seed));
    }
}
```

- [ ] **Step 5: Run the test**

Run: `.tools/apache-maven-3.9.11/bin/mvn -B -q -f bridge/pom.xml test -Dtest=ForgeRuntimeTest`
Expected: 2 tests pass. If boot throws, read the stack trace for the missing `IGuiBase` behavior (Forge's desktop `Main` notes `ForgeConstants` resolves `ASSETS_DIR` through `GuiBase.getInterface()`), fix in `HeadlessGuiBase`, and record what you changed in `docs/STATUS.md`.

- [ ] **Step 6: Commit**

```bash
git add bridge/src
git commit -m "feat(bridge): boot Forge headless and load reference precons"
```

### Task 8: NDJSON writer

**Files:** Create `bridge/src/main/java/magicsim/bridge/Ndjson.java`, test `bridge/src/test/java/magicsim/bridge/NdjsonTest.java`

- [ ] **Step 1: Write the failing test**
```java
package magicsim.bridge;

import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;

class NdjsonTest {
    @Test
    void writesOneJsonObjectPerLine() {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        Ndjson nd = new Ndjson(out);
        nd.write(Map.of("type", "ready"));
        nd.write(Map.of("type", "error", "message", "x"));
        String[] lines = out.toString(StandardCharsets.UTF_8).split("\n");
        assertEquals(2, lines.length);
        assertEquals("{\"type\":\"ready\"}", lines[0]);
    }
}
```

- [ ] **Step 2: Run** `... test -Dtest=NdjsonTest` — Expected: FAIL (no `Ndjson`).

- [ ] **Step 3: Implement**
```java
package magicsim.bridge;

import com.google.gson.Gson;
import com.google.gson.GsonBuilder;

import java.io.IOException;
import java.io.OutputStream;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;

public final class Ndjson {
    private final OutputStream out;
    private final Gson gson = new GsonBuilder().disableHtmlEscaping().serializeNulls().create();

    public Ndjson(OutputStream out) {
        this.out = out;
    }

    public synchronized void write(Object message) {
        try {
            out.write((gson.toJson(message) + "\n").getBytes(StandardCharsets.UTF_8));
            out.flush();
        } catch (IOException e) {
            throw new UncheckedIOException("[Ndjson:write] Failed to write message", e);
        }
    }
}
```

- [ ] **Step 4: Run** — Expected: PASS. **Step 5: Commit** `feat(bridge): add NDJSON writer`.

### Task 9: All-AI seeded 4-player game

**Files:** Create `bridge/src/main/java/magicsim/bridge/GameRunner.java`, test `bridge/src/test/java/magicsim/bridge/AllAiGameTest.java`

- [ ] **Step 1: Write the failing test**
```java
package magicsim.bridge;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AllAiGameTest {
    @BeforeAll
    static void boot() {
        ForgeRuntime.boot(Path.of(System.getProperty("forge.gui.dir")));
    }

    @Test
    void seededGameReachesGameOverAndIsRepeatable() {
        ByteArrayOutputStream firstLog = new ByteArrayOutputStream();
        ByteArrayOutputStream secondLog = new ByteArrayOutputStream();
        GameRunner.Outcome first = GameRunner.runAllAi(ForgeRuntime.REFERENCE_PRECONS, 42L, 8, new Ndjson(firstLog));
        GameRunner.Outcome second = GameRunner.runAllAi(ForgeRuntime.REFERENCE_PRECONS, 42L, 8, new Ndjson(secondLog));
        assertTrue(first.turns() > 0);
        assertEquals(first, second, "same seed must give the same outcome");
        assertEquals(withoutCardIds(firstLog), withoutCardIds(secondLog), "same seed must give the same event stream");
    }

    /** Card ids come from a JVM-wide counter, so a second game in the same JVM numbers its cards differently. */
    private static String withoutCardIds(ByteArrayOutputStream log) {
        return log.toString(StandardCharsets.UTF_8).replaceAll("\\(\\d+\\)", "(#)");
    }
}
```

- [ ] **Step 2: Run** `... test -Dtest=AllAiGameTest` — Expected: FAIL (no `GameRunner`).

- [ ] **Step 3: Implement**
```java
package magicsim.bridge;

import com.google.common.eventbus.Subscribe;
import forge.LobbyPlayer;
import forge.game.Game;
import forge.game.GameOutcome;
import forge.game.GameRules;
import forge.game.GameType;
import forge.game.Match;
import forge.game.GameEndReason;
import forge.game.event.GameEvent;
import forge.game.event.GameEventTurnBegan;
import forge.game.player.RegisteredPlayer;
import forge.player.GamePlayerUtil;

import java.util.ArrayList;
import java.util.EnumSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;

public final class GameRunner {
    public record Outcome(String winner, int turns, boolean draw) {}

    private GameRunner() {}

    static GameRules commanderRules() {
        GameRules rules = new GameRules(GameType.Commander);
        rules.setAppliedVariants(EnumSet.of(GameType.Commander));
        return rules;
    }

    // ponytail: Forge AI can spend many CPU-minutes per decision on crowded boards, so all-AI games
    // end as a draw after turnLimit. A wall-clock cap (Forge's SimulateMatch) would break determinism.
    public static Outcome runAllAi(List<String> precons, long seed, int turnLimit, Ndjson out) {
        ForgeRuntime.seed(seed);
        List<RegisteredPlayer> players = new ArrayList<>();
        for (int i = 0; i < precons.size(); i++) {
            RegisteredPlayer rp = RegisteredPlayer.forCommander(ForgeRuntime.loadPrecon(precons.get(i)));
            rp.setPlayer(GamePlayerUtil.createAiPlayer("Ai(" + (i + 1) + ")", i));
            players.add(rp);
        }
        Match match = new Match(commanderRules(), players, "MagicSim");
        Game game = match.createGame();
        game.subscribeToEvents(new EventForwarder(out));
        game.subscribeToEvents(new TurnCap(game, turnLimit));
        match.startGame(game); // blocks until the game ends
        return report(game, out);
    }


    static Outcome report(Game game, Ndjson out) {
        GameOutcome outcome = game.getOutcome();
        // A forced Draw marks every surviving player as having won, so the winner is only meaningful otherwise.
        boolean draw = outcome.getWinCondition() == GameEndReason.Draw || outcome.isDraw();
        LobbyPlayer winner = draw ? null : outcome.getWinningLobbyPlayer();
        Outcome result = new Outcome(winner == null ? null : winner.getName(), outcome.getLastTurnNumber(), draw);
        Map<String, Object> msg = new LinkedHashMap<>();
        msg.put("type", "gameOver");
        msg.put("winner", result.winner());
        msg.put("turns", result.turns());
        msg.put("draw", result.draw());
        out.write(msg);
        return result;
    }

    static final class TurnCap {
        private final Game game;
        private final int turnLimit;

        TurnCap(Game game, int turnLimit) {
            this.game = game;
            this.turnLimit = turnLimit;
        }

        @Subscribe
        public void onTurn(GameEventTurnBegan event) {
            if (event.turnNumber() > turnLimit) game.setGameOver(GameEndReason.Draw);
        }
    }

    /** M1: forwards every Forge game event as an untyped NDJSON event. M2 replaces this with typed events. */
    static final class EventForwarder {
        private final Ndjson out;
        private final AtomicInteger seq = new AtomicInteger();

        EventForwarder(Ndjson out) {
            this.out = out;
        }

        @Subscribe
        public void onEvent(GameEvent event) {
            Map<String, Object> msg = new LinkedHashMap<>();
            msg.put("type", "event");
            msg.put("seq", seq.getAndIncrement());
            msg.put("kind", event.getClass().getSimpleName());
            msg.put("text", String.valueOf(event));
            out.write(msg);
        }
    }
}
```

- [ ] **Step 4: Run** — Expected: PASS in well under a minute (the spike took about 2 s per 8-turn game). If the event streams differ, Forge has an unseeded randomness source: find it with `rg -n "new Random\\(|Math.random|ThreadLocalRandom" forge/forge-game forge/forge-ai`, record it in `docs/STATUS.md`, and relax the test to assert only that both games finish (do not edit Forge).

- [ ] **Step 5: Commit** `feat(bridge): run seeded 4-player Commander games with Forge AI`.

### Task 10: `JsonRemote` — Forge GUI calls as NDJSON

**Files:** Create `bridge/src/main/java/magicsim/bridge/SeatClient.java`, `bridge/src/main/java/magicsim/bridge/JsonRemote.java`, test `bridge/src/test/java/magicsim/bridge/JsonRemoteTest.java`

- [ ] **Step 1: Write the failing test**
```java
package magicsim.bridge;

import forge.gamemodes.net.ProtocolMethod;
import forge.gamemodes.net.event.GuiGameEvent;
import org.junit.jupiter.api.Test;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.List;

import static org.junit.jupiter.api.Assertions.*;

class JsonRemoteTest {
    @Test
    void sendWritesAGuiCallAndSendAndWaitReturnsTheClientsReply() {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        SeatClient client = call -> call.method() == ProtocolMethod.showConfirmDialog ? Boolean.TRUE : null;
        JsonRemote remote = new JsonRemote(new Ndjson(out), client);

        remote.send(new GuiGameEvent(ProtocolMethod.showPromptMessage, null, "Your turn", null));
        Object reply = remote.sendAndWait(new GuiGameEvent(ProtocolMethod.showConfirmDialog, "Keep hand?", "Mulligan", "Keep", "Mulligan", true));

        assertEquals(Boolean.TRUE, reply);
        List<String> lines = out.toString(StandardCharsets.UTF_8).lines().toList();
        assertEquals(2, lines.size());
        assertTrue(lines.get(0).contains("\"method\":\"showPromptMessage\""));
        assertTrue(lines.get(1).contains("\"awaitsReply\":true"));
    }
}
```

- [ ] **Step 2: Run** `... test -Dtest=JsonRemoteTest` — Expected: FAIL.

- [ ] **Step 3: Implement**

`SeatClient.java`:
```java
package magicsim.bridge;

import forge.gamemodes.net.ProtocolMethod;

/** Answers a human seat's GUI calls. M1: a scripted test client. M3: the server over stdio. */
public interface SeatClient {
    record Call(int id, ProtocolMethod method, Object[] args) {}

    /** Called for every GUI call; the return value is only used when the call awaits a reply. */
    Object onCall(Call call);
}
```

`JsonRemote.java`:
```java
package magicsim.bridge;

import forge.gamemodes.net.IRemote;
import forge.gamemodes.net.event.GuiGameEvent;
import forge.gamemodes.net.event.IdentifiableNetEvent;
import forge.gamemodes.net.event.NetEvent;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** The bridge's one Forge seam: ProtocolGuiGame hands every IGuiGame call to this IRemote. */
public final class JsonRemote implements IRemote {
    private final Ndjson out;
    private final SeatClient client;

    public JsonRemote(Ndjson out, SeatClient client) {
        this.out = out;
        this.client = client;
    }

    @Override
    public void send(NetEvent event) {
        if (event instanceof GuiGameEvent gge) {
            emit(gge, false);
            client.onCall(new SeatClient.Call(gge.getId(), gge.getMethod(), gge.getObjects()));
        }
    }

    @Override
    public Object sendAndWait(IdentifiableNetEvent event) {
        if (!(event instanceof GuiGameEvent gge)) {
            throw new IllegalArgumentException("[JsonRemote:sendAndWait] Unexpected event type — " + event.getClass().getName());
        }
        emit(gge, true);
        return client.onCall(new SeatClient.Call(gge.getId(), gge.getMethod(), gge.getObjects()));
    }

    private void emit(GuiGameEvent gge, boolean awaitsReply) {
        Map<String, Object> msg = new LinkedHashMap<>();
        msg.put("type", "gui");
        msg.put("id", awaitsReply ? gge.getId() : null);
        msg.put("method", gge.getMethod().name());
        msg.put("awaitsReply", awaitsReply);
        List<String> args = new ArrayList<>();
        for (Object o : gge.getObjects()) {
            args.add(o == null ? null : String.valueOf(o)); // ponytail: toString summaries; M2 emits typed decisions
        }
        msg.put("args", args);
        out.write(msg);
    }
}
```

- [ ] **Step 4: Run** — Expected: PASS. **Step 5: Commit** `feat(bridge): route Forge GUI calls through JsonRemote`.

### Task 11: Scripted human seat plays a full game

**Files:** Create `bridge/src/test/java/magicsim/bridge/ScriptedSeatClient.java`, `bridge/src/test/java/magicsim/bridge/ScriptedHumanGameTest.java`; modify `GameRunner.java` (add `runWithHumanSeat`)

- [ ] **Step 1: Write the failing test**
```java
package magicsim.bridge;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

import java.io.ByteArrayOutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Path;
import java.util.concurrent.TimeUnit;

import static org.junit.jupiter.api.Assertions.*;

class ScriptedHumanGameTest {
    @BeforeAll
    static void boot() {
        ForgeRuntime.boot(Path.of(System.getProperty("forge.gui.dir")));
    }

    @Test
    @Timeout(value = 5, unit = TimeUnit.MINUTES)
    void gameWithOneScriptedHumanSeatReachesGameOver() {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        Ndjson out = new Ndjson(bytes);
        GameRunner.Outcome outcome = GameRunner.runWithHumanSeat(ForgeRuntime.REFERENCE_PRECONS, 7L, 8, out, ScriptedSeatClient::new);
        assertTrue(outcome.turns() > 0);
        String log = bytes.toString(StandardCharsets.UTF_8);
        assertTrue(log.contains("\"type\":\"gui\""), "human seat produced GUI calls");
        assertTrue(log.contains("\"type\":\"gameOver\""));
    }
}
```

- [ ] **Step 2: Run** `... test -Dtest=ScriptedHumanGameTest` — Expected: FAIL (no `runWithHumanSeat`, no `ScriptedSeatClient`).

- [ ] **Step 3: Add `runWithHumanSeat` to `GameRunner`**
```java
    // add imports:
    // import forge.game.player.Player;
    // import forge.gamemodes.match.HostedMatch;
    // import forge.gamemodes.net.ProtocolGuiGame;
    // import forge.gui.interfaces.IGuiGame;
    // import forge.player.LobbyPlayerHuman;
    // import forge.player.PlayerControllerHuman;
    // import java.util.HashMap;
    // import java.util.concurrent.CountDownLatch;
    // import java.util.concurrent.TimeUnit;
    // import java.util.function.Function;
    // import forge.game.event.GameEventGameFinished;

    /** Seat 1 is a human driven by the given client; seats 2-4 are Forge AI. */
    public static Outcome runWithHumanSeat(List<String> precons, long seed, int turnLimit, Ndjson out,
                                           Function<PlayerControllerHumanRef, SeatClient> clientFactory) {
        ForgeRuntime.seed(seed);
        PlayerControllerHumanRef humanRef = new PlayerControllerHumanRef();
        CountDownLatch finished = new CountDownLatch(1);
        HostedMatch hosted = new HostedMatch();
        SeatClient seat = clientFactory.apply(humanRef);
        // HostedMatch.startGame() creates the Game and sends this seat's GUI setGameView on the calling thread,
        // before the game thread starts. Its start hook only runs at turn 1, after the starting-player and
        // mulligan prompts, so the first GUI call is the earliest race-free point to attach to the game.
        SeatClient attachOnFirstCall = call -> {
            if (humanRef.get() == null) {
                Game game = hosted.getGame();
                game.subscribeToEvents(new EventForwarder(out));
                game.subscribeToEvents(new TurnCap(game, turnLimit));
                game.subscribeToEvents(new Object() {
                    @Subscribe public void onFinished(GameEventGameFinished e) { finished.countDown(); }
                });
                for (Player p : game.getPlayers()) {
                    if (p.getController() instanceof PlayerControllerHuman pch) humanRef.set(pch);
                }
            }
            return seat.onCall(call);
        };
        List<RegisteredPlayer> players = new ArrayList<>();
        Map<RegisteredPlayer, IGuiGame> guis = new HashMap<>();
        for (int i = 0; i < precons.size(); i++) {
            RegisteredPlayer rp = RegisteredPlayer.forCommander(ForgeRuntime.loadPrecon(precons.get(i)));
            if (i == 0) {
                rp.setPlayer(new LobbyPlayerHuman("You"));
                guis.put(rp, new ProtocolGuiGame(new JsonRemote(out, attachOnFirstCall)));
            } else {
                rp.setPlayer(GamePlayerUtil.createAiPlayer("Ai(" + (i + 1) + ")", i));
            }
            players.add(rp);
        }
        hosted.startMatch(commanderRules(), EnumSet.of(GameType.Commander), players, guis, null);
        try {
            if (!finished.await(5, TimeUnit.MINUTES)) {
                throw new IllegalStateException("[GameRunner:runWithHumanSeat] Game did not finish in 5 minutes — seed " + seed);
            }
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException("[GameRunner:runWithHumanSeat] Interrupted", e);
        }
        return report(hosted.getGame(), out);
    }

    /** Filled once the game creates the human seat's controller. */
    public static final class PlayerControllerHumanRef {
        private volatile PlayerControllerHuman value;
        void set(PlayerControllerHuman v) { value = v; }
        public PlayerControllerHuman get() { return value; }
    }

    /** Filled once the game creates the human seat's controller. */
    public static final class PlayerControllerHumanRef {
        private volatile PlayerControllerHuman value;
        void set(PlayerControllerHuman v) { value = v; }
        public PlayerControllerHuman get() { return value; }
    }

    static Outcome report(Game game, Ndjson out) {
        GameOutcome outcome = game.getOutcome();
        // A forced Draw marks every surviving player as having won, so the winner is only meaningful otherwise.
        boolean draw = outcome.getWinCondition() == GameEndReason.Draw || outcome.isDraw();
        LobbyPlayer winner = draw ? null : outcome.getWinningLobbyPlayer();
        Outcome result = new Outcome(winner == null ? null : winner.getName(), outcome.getLastTurnNumber(), draw);
        Map<String, Object> msg = new LinkedHashMap<>();
        msg.put("type", "gameOver");
        msg.put("winner", result.winner());
        msg.put("turns", result.turns());
        msg.put("draw", result.draw());
        out.write(msg);
        return result;
    }

```

- [ ] **Step 4: Implement `ScriptedSeatClient`** (test sources)
```java
package magicsim.bridge;

import forge.gamemodes.match.input.Input;
import forge.gamemodes.match.input.InputSelectEntitiesFromList;
import forge.gamemodes.net.ProtocolMethod;
import forge.game.card.CardView;
import forge.player.PlayerControllerHuman;

import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Plays the human seat as passively as possible: keeps its hand, passes priority, declares nothing,
 * and makes the first legal pick whenever Forge forces a choice. Enough to prove the seam end to end.
 */
final class ScriptedSeatClient implements SeatClient {
    private final GameRunner.PlayerControllerHumanRef human;
    // Inputs must be answered off the game thread, like a real client would.
    private final ExecutorService responder = Executors.newSingleThreadExecutor(r -> {
        Thread t = new Thread(r, "scripted-seat");
        t.setDaemon(true);
        return t;
    });
    private volatile List<CardView> selectable = List.of();

    ScriptedSeatClient(GameRunner.PlayerControllerHumanRef human) {
        this.human = human;
    }

    @Override
    @SuppressWarnings("unchecked")
    public Object onCall(Call call) {
        Object[] a = call.args();
        ProtocolMethod m = call.method();
        switch (m) {
            case setSelectables -> {
                List<CardView> cards = new ArrayList<>();
                if (a[0] instanceof Iterable<?> it) for (Object o : it) if (o instanceof CardView cv) cards.add(cv);
                selectable = cards;
                return null;
            }
            case updateButtons -> {
                // args: owner, okLabel, cancelLabel, okEnabled, cancelEnabled, focusOk
                boolean okEnabled = Boolean.TRUE.equals(a[3]);
                boolean cancelEnabled = Boolean.TRUE.equals(a[4]);
                responder.submit(() -> answerInput(okEnabled, cancelEnabled));
                return null;
            }
            case confirm -> { return a[2]; }                       // defaultIsYes
            case showConfirmDialog -> { return a[4]; }             // defaultYes
            case showOptionDialog -> { return a[4]; }              // defaultOption
            case showInputDialog -> { return a[3]; }               // initialInput
            case getChoices -> {                                   // message, min, max, choices, selected, display
                int min = (Integer) a[1];
                List<Object> choices = new ArrayList<>((Collection<Object>) a[3]);
                return new ArrayList<>(choices.subList(0, Math.min(Math.max(min, 0), choices.size())));
            }
            case chooseSingleEntityForEffect -> {                  // title, options, delayedReveal, isOptional
                List<Object> options = (List<Object>) a[1];
                boolean optional = Boolean.TRUE.equals(a[3]);
                return optional || options.isEmpty() ? null : options.get(0);
            }
            case chooseEntitiesForEffect -> {                      // title, options, min, max, delayedReveal
                List<Object> options = (List<Object>) a[1];
                int min = (Integer) a[2];
                return new ArrayList<>(options.subList(0, Math.min(min, options.size())));
            }
            default -> { return null; }
        }
    }

    private void answerInput(boolean okEnabled, boolean cancelEnabled) {
        PlayerControllerHuman pch = human.get();
        if (pch == null) return;
        Input input = pch.getInputProxy().getInput();
        if (input == null) return;
        if (okEnabled) { pch.selectButtonOk(); return; }
        if (!selectable.isEmpty()) { pch.selectCard(selectable.get(0), List.of(), null); return; }
        if (cancelEnabled) { pch.selectButtonCancel(); return; }
        // Player choices (such as who starts) are not sent as selectables; picking yourself is the passive answer.
        if (input instanceof InputSelectEntitiesFromList<?>) { pch.selectPlayer(pch.getPlayer().getView(), null); return; }
        System.err.println("[ScriptedSeatClient:answerInput] No answer for input — " + input.getClass().getSimpleName());
    }
}
```
Any `sendAndWait` method this client returns `null` for, where Forge needs a value (`order`, `assignCombatDamage`, `assignGenericAmount`, `manipulateCardList`, `getAbilityToPlay`), will surface as a stall or exception in Step 5; add a case that returns Forge's "do nothing" value for it (for example the unchanged source list for `order`) and note it in `docs/STATUS.md`.

- [ ] **Step 5: Run and debug until it passes**

Run: `.tools/apache-maven-3.9.11/bin/mvn -B -f bridge/pom.xml test -Dtest=ScriptedHumanGameTest`
Expected: PASS in about 20 s (spike: the seat answered 71 prompts and the game reached the 8-turn cap as a draw). If it times out: set `-Dsurefire.printSummary=true`, add a temporary log of `pch.getInputProxy().getInput().getClass().getSimpleName()` in `answerInput`, rerun, and add handling for the Input it stalled on (for example cleanup discard: OK is disabled until a card is selected, so select the first card in hand from `pch.getPlayer().getCardsIn(ZoneType.Hand)` when `selectable` is empty). Record each Input you had to handle in `docs/STATUS.md`; M2 turns this list into typed decisions.

- [ ] **Step 6: Commit** `feat(bridge): play a full game with a scripted human seat through ProtocolGuiGame`.

### Task 12: stdio entry point

**Files:** Create `bridge/src/main/java/magicsim/bridge/Main.java`

- [ ] **Step 1: Implement**
```java
package magicsim.bridge;

import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.Map;

/** M1 entry point: `java -jar forge-bridge.jar [seed]` plays one all-AI reference game and exits. */
public final class Main {
    public static void main(String[] args) {
        Ndjson out = new Ndjson(System.out);
        System.setOut(System.err); // stdout is reserved for protocol messages; Forge logging goes to stderr
        Path guiDir = Path.of(System.getenv().getOrDefault("FORGE_GUI_DIR", "forge/forge-gui"));
        ForgeRuntime.boot(guiDir);
        Map<String, Object> ready = new LinkedHashMap<>();
        ready.put("type", "ready");
        ready.put("forgeVersion", forge.util.BuildInfo.getVersionString());
        out.write(ready);
        long seed = args.length > 0 ? Long.parseLong(args[0]) : System.nanoTime();
        GameRunner.runAllAi(ForgeRuntime.REFERENCE_PRECONS, seed, 30, out);
        System.exit(0);
    }
}
```

- [ ] **Step 2: Package and run**

Run: `.tools/apache-maven-3.9.11/bin/mvn -B -q -f bridge/pom.xml package -DskipTests && java -jar bridge/target/forge-bridge.jar 42 2>/dev/null | head -1 && java -jar bridge/target/forge-bridge.jar 42 2>/dev/null | tail -1`
Expected: first line `{"type":"ready","forgeVersion":"GIT"}`; last line `{"type":"gameOver","winner":null,"turns":31,"draw":true}` (spike result for seed 42: about 10 s and 6,322 lines; all-AI Commander games often reach the 30-turn cap).

- [ ] **Step 3: Validate the output against the protocol schemas**

Run: `java -jar bridge/target/forge-bridge.jar 42 2>/dev/null > /tmp/bridge.ndjson && node -e 'import("./packages/protocol/src/index.ts").then(({BridgeMessageSchema})=>{const ls=require("fs").readFileSync("/tmp/bridge.ndjson","utf8").trim().split("\n");for(const l of ls)BridgeMessageSchema.parse(JSON.parse(l));console.log("valid",ls.length)})'`
Expected: `valid <N>` with no zod error.

- [ ] **Step 4: Commit** `feat(bridge): add stdio entry point`.

### Task 13: M1 gate + handoff

- [ ] **Step 1:** Run `bash scripts/verify.sh`. Expected: all bridge tests (Classpath, ForgeRuntime ×2, Ndjson, AllAiGame, JsonRemote, ScriptedHumanGame) and JS tests pass; record the exact pass counts.
- [ ] **Step 2:** Update `docs/STATUS.md` (Status, SHAs, the list of Inputs/GUI methods the scripted client had to handle, any nondeterminism found, timings).
- [ ] **Step 3:** Push; CI green (`gh run watch --exit-status`); update the PR body with evidence and flip to ready per the writing-prs skill. **M1 gate met.** Next: write the M2 plan with superpowers:writing-plans.
