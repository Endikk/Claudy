# Onglet Ports Claude — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ajouter à Claudy un onglet listant les ports TCP en écoute lancés par Claude Code — session vivante comme orphelins — et permettant de les tuer un par un.

**Architecture:** L'attribution repose sur les variables d'environnement héritées (`CLAUDECODE`, `CLAUDE_CODE_ENTRYPOINT`, `CLAUDE_PROJECT_DIR`), lues par `sysctl(KERN_PROCARGS2)` : elles survivent à la mort de la session, donc aucune persistance n'est nécessaire. `lsof` fournit les listeners, `ps` l'arbre de process (utilisé uniquement pour protéger les sessions Claude vivantes du kill). Tout le parsing est isolé dans des fonctions pures testables ; les effets de bord (sous-process, signaux) passent par des protocoles injectables.

**Tech Stack:** Swift 5.0, SwiftUI, macOS 13+, XCTest, Xcode project `objectVersion = 70` avec dossiers synchronisés.

**Spec:** `docs/superpowers/specs/2026-09-03-onglet-ports-claude-design.md`

## Global Constraints

- Cible : `MACOSX_DEPLOYMENT_TARGET = 13.0`, `SWIFT_VERSION = 5.0`.
- Les fichiers sous `Claudy/` sont pris automatiquement par le target (dossier synchronisé) — ne jamais éditer `project.pbxproj` pour ajouter un fichier source.
- Aucune valeur de style en dur dans les vues : couleurs, polices et métriques passent par `Theme`.
- Sous-process : chemin absolu de l'exécutable, jamais de shell, timeout explicite, échec tracé via `DiagnosticLog` — modèle : `Claudy/Services/ClaudeCodeCredentials.swift`.
- L'environnement d'un process n'est jamais retourné, affiché, journalisé ni écrit sur disque : seuls le booléen de présence et la valeur de `CLAUDE_PROJECT_DIR` sortent de `ProcessEnvironment`.
- Aucun test n'envoie de signal à un process réel.
- Commentaires de code en anglais, comme le reste du projet ; ils disent *pourquoi*, pas *quoi*.
- Denylist d'attribution, quels que soient les marqueurs : `OrbStack`, `Docker`, `com.docker.backend`.
- Chaque commit se termine par `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

### Task 1: Target de test

**Files:**
- Modify: `Claudy.xcodeproj/project.pbxproj`
- Modify: `Claudy.xcodeproj/xcshareddata/xcschemes/Claudy.xcscheme:30-31`
- Create: `ClaudyTests/SmokeTests.swift`

**Interfaces:**
- Consumes: rien
- Produces: la commande `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS'` — utilisée par toutes les tâches suivantes.

- [ ] **Step 1: Écrire le test de fumée**

Créer `ClaudyTests/SmokeTests.swift` :

```swift
import XCTest
@testable import Claudy

final class SmokeTests: XCTestCase {
    func testTestTargetRuns() {
        XCTAssertEqual(Theme.Metric.fullWidth, 340)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -20`
Expected: FAIL — `Scheme Claudy is not currently configured for the test action`.

- [ ] **Step 3: Ajouter le target de test au pbxproj**

Les IDs `1A00…0001` à `1A00…000F` sont pris. Utiliser `0010` et suivants.

Dans `/* Begin PBXFileReference section */`, après la ligne `Claudy.app` :

```
		1A0000000000000000000010 /* ClaudyTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = ClaudyTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
```

Dans `/* Begin PBXFileSystemSynchronizedRootGroup section */`, après la ligne `Claudy` :

```
		1A0000000000000000000011 /* ClaudyTests */ = {isa = PBXFileSystemSynchronizedRootGroup; explicitFileTypes = {}; explicitFolders = (); path = ClaudyTests; sourceTree = "<group>"; };
```

Dans le groupe racine `1A0000000000000000000002`, ajouter `1A0000000000000000000011 /* ClaudyTests */,` après l'entrée `Claudy`.
Dans le groupe `Products`, ajouter `1A0000000000000000000010 /* ClaudyTests.xctest */,`.

Dans `/* Begin PBXNativeTarget section */`, après le target `Claudy` :

```
		1A0000000000000000000012 /* ClaudyTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 1A0000000000000000000013 /* Build configuration list for PBXNativeTarget "ClaudyTests" */;
			buildPhases = (
				1A0000000000000000000014 /* Sources */,
				1A0000000000000000000015 /* Frameworks */,
			);
			buildRules = (
			);
			dependencies = (
				1A0000000000000000000016 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				1A0000000000000000000011 /* ClaudyTests */,
			);
			name = ClaudyTests;
			packageProductDependencies = (
			);
			productName = ClaudyTests;
			productReference = 1A0000000000000000000010 /* ClaudyTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
```

Ajouter les phases de build, dans leurs sections respectives :

```
		1A0000000000000000000014 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

```
		1A0000000000000000000015 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
```

Créer les sections de dépendance (les deux sections n'existent pas encore, les ajouter avant `/* Begin XCBuildConfiguration section */`) :

```
/* Begin PBXContainerItemProxy section */
		1A0000000000000000000017 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 1A0000000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 1A0000000000000000000004;
			remoteInfo = Claudy;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXTargetDependency section */
		1A0000000000000000000016 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 1A0000000000000000000004 /* Claudy */;
			targetProxy = 1A0000000000000000000017 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */
```

Dans `/* Begin XCBuildConfiguration section */`, après la configuration `1A00…000F` :

```
		1A0000000000000000000018 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.claudy.ClaudyTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				PROVISIONING_PROFILE_SPECIFIER = "";
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Claudy.app/Contents/MacOS/Claudy";
			};
			name = Debug;
		};
		1A0000000000000000000019 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				DEVELOPMENT_TEAM = "";
				GENERATE_INFOPLIST_FILE = YES;
				MACOSX_DEPLOYMENT_TARGET = 13.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.claudy.ClaudyTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				PROVISIONING_PROFILE_SPECIFIER = "";
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Claudy.app/Contents/MacOS/Claudy";
			};
			name = Release;
		};
```

Dans `/* Begin XCConfigurationList section */` :

```
		1A0000000000000000000013 /* Build configuration list for PBXNativeTarget "ClaudyTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				1A0000000000000000000018 /* Debug */,
				1A0000000000000000000019 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
```

Enfin, dans `PBXProject`, ajouter `1A0000000000000000000012 /* ClaudyTests */,` à la liste `targets`, et dans `TargetAttributes` :

```
					1A0000000000000000000012 = {
						CreatedOnToolsVersion = 26.6;
						TestTargetID = 1A0000000000000000000004;
					};
```

- [ ] **Step 4: Déclarer le testable dans le scheme**

Dans `Claudy.xcodeproj/xcshareddata/xcschemes/Claudy.xcscheme`, remplacer les lignes 30-31 (`<Testables>` / `</Testables>` vides) par :

```xml
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "1A0000000000000000000012"
               BuildableName = "ClaudyTests.xctest"
               BlueprintName = "ClaudyTests"
               ReferencedContainer = "container:Claudy.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
```

- [ ] **Step 5: Vérifier que le projet s'ouvre et que le test passe**

Run: `xcodebuild -list -project Claudy.xcodeproj`
Expected: `ClaudyTests` apparaît dans `Targets`.

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `TEST SUCCEEDED`, 1 test exécuté.

Si le pbxproj est rejeté (`Unable to open base configuration` ou parse error), revenir en arrière avec `git checkout -- Claudy.xcodeproj/project.pbxproj` et recommencer l'étape 3 bloc par bloc.

- [ ] **Step 6: Commit**

```bash
git add Claudy.xcodeproj ClaudyTests
git commit -m "$(cat <<'EOF'
test: add ClaudyTests unit test target

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: ProcessEnvironment — lecture des marqueurs Claude

**Files:**
- Create: `Claudy/Services/ProcessEnvironment.swift`
- Test: `ClaudyTests/ProcessEnvironmentTests.swift`

**Interfaces:**
- Consumes: rien
- Produces:
  - `struct ProcessEnvironment.Markers: Equatable { let isClaude: Bool; let projectDirectory: String? }`
  - `static func ProcessEnvironment.markers(pid: pid_t) -> Markers?`
  - `static func ProcessEnvironment.parse(_ buffer: [UInt8]) -> Markers?`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `ClaudyTests/ProcessEnvironmentTests.swift` :

```swift
import XCTest
@testable import Claudy

final class ProcessEnvironmentTests: XCTestCase {

    /// Builds a KERN_PROCARGS2 buffer: argc, exec path, padding, arguments, environment.
    private func buffer(argc: Int32, execPath: String, args: [String], env: [String]) -> [UInt8] {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: argc.littleEndian) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(execPath.utf8))
        bytes.append(contentsOf: [0, 0, 0])
        for argument in args {
            bytes.append(contentsOf: Array(argument.utf8))
            bytes.append(0)
        }
        for entry in env {
            bytes.append(contentsOf: Array(entry.utf8))
            bytes.append(0)
        }
        return bytes
    }

    func testDetectsClaudeCodeMarker() {
        let raw = buffer(
            argc: 2, execPath: "/usr/bin/python3",
            args: ["python3", "-m"],
            env: ["PATH=/usr/bin", "CLAUDECODE=1", "TERM=xterm"]
        )
        let markers = ProcessEnvironment.parse(raw)
        XCTAssertEqual(markers, ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil))
    }

    func testReadsProjectDirectory() {
        let raw = buffer(
            argc: 1, execPath: "/bin/bun", args: ["bun"],
            env: ["CLAUDE_PROJECT_DIR=/Users/x/Dev/Surikat"]
        )
        let markers = ProcessEnvironment.parse(raw)
        XCTAssertEqual(markers?.isClaude, true)
        XCTAssertEqual(markers?.projectDirectory, "/Users/x/Dev/Surikat")
    }

    func testEntrypointAloneIsEnough() {
        let raw = buffer(argc: 1, execPath: "/bin/zsh", args: ["zsh"],
                         env: ["CLAUDE_CODE_ENTRYPOINT=cli"])
        XCTAssertEqual(ProcessEnvironment.parse(raw)?.isClaude, true)
    }

    /// The decisive case: a command line that merely mentions the marker must not attribute
    /// the process. Arguments are skipped by counting argc, never by searching for text.
    func testCommandLineMentionIsNotAnAttribution() {
        let raw = buffer(
            argc: 2, execPath: "/bin/echo",
            args: ["echo", "CLAUDECODE=1"],
            env: ["PATH=/usr/bin"]
        )
        XCTAssertEqual(ProcessEnvironment.parse(raw)?.isClaude, false)
    }

    func testUnrelatedProcessHasNoMarkers() {
        let raw = buffer(argc: 1, execPath: "/usr/bin/node", args: ["node"],
                         env: ["PATH=/usr/bin", "HOME=/Users/x"])
        XCTAssertEqual(ProcessEnvironment.parse(raw), ProcessEnvironment.Markers(isClaude: false, projectDirectory: nil))
    }

    func testTruncatedBufferReturnsNil() {
        XCTAssertNil(ProcessEnvironment.parse([1, 0]))
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/ProcessEnvironmentTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ProcessEnvironment' in scope`.

- [ ] **Step 3: Implémenter**

Créer `Claudy/Services/ProcessEnvironment.swift` :

```swift
import Foundation

/// Reads the Claude Code markers out of a process's environment.
///
/// The environment is inherited by every descendant and outlives the session that created it,
/// so it is the only attribution signal that still holds once launchd has reparented an
/// orphaned server. A process environment routinely carries tokens: nothing but the presence
/// flag and the project directory ever leaves this type.
enum ProcessEnvironment {

    struct Markers: Equatable {
        let isClaude: Bool
        let projectDirectory: String?
    }

    static func markers(pid: pid_t) -> Markers? {
        guard let raw = procArgs(pid: pid) else { return nil }
        return parse(raw)
    }

    /// `KERN_PROCARGS2` layout: argc, the executable path, padding NULs, then exactly argc
    /// arguments, then the environment. The arguments are skipped by counting, never by
    /// searching: a command line containing `CLAUDECODE=1` would otherwise attribute a process
    /// that Claude never launched.
    static func parse(_ raw: [UInt8]) -> Markers? {
        guard raw.count > 4 else { return nil }

        let argc = Int(UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16 | UInt32(raw[3]) << 24)
        guard argc >= 0 else { return nil }

        var index = 4
        while index < raw.count, raw[index] != 0 { index += 1 }
        while index < raw.count, raw[index] == 0 { index += 1 }

        var skipped = 0
        while skipped < argc, index < raw.count {
            while index < raw.count, raw[index] != 0 { index += 1 }
            index += 1
            skipped += 1
        }
        guard skipped == argc else { return nil }

        var isClaude = false
        var projectDirectory: String?
        var start = index

        while index <= raw.count {
            let isEnd = index == raw.count
            if isEnd || raw[index] == 0 {
                if start < index {
                    let entry = String(decoding: raw[start..<index], as: UTF8.self)
                    if entry.hasPrefix("CLAUDECODE=") || entry.hasPrefix("CLAUDE_CODE_ENTRYPOINT=") {
                        isClaude = true
                    } else if let value = entry.dropPrefix("CLAUDE_PROJECT_DIR=") {
                        isClaude = true
                        projectDirectory = value
                    }
                }
                start = index + 1
            }
            index += 1
        }

        return Markers(isClaude: isClaude, projectDirectory: projectDirectory)
    }

    /// The buffer is sized from `kern.argmax`: asking `sysctl` for the size of
    /// `KERN_PROCARGS2` is not supported and fails with EINVAL.
    private static func procArgs(pid: pid_t) -> [UInt8]? {
        var argmaxMib: [Int32] = [CTL_KERN, KERN_ARGMAX]
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        guard sysctl(&argmaxMib, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }

        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = Int(argmax)
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return Array(buffer.prefix(size))
    }
}

private extension String {
    /// The value behind a `KEY=` prefix, or nil when the prefix does not match.
    func dropPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/ProcessEnvironmentTests 2>&1 | tail -20`
Expected: PASS, 6 tests.

- [ ] **Step 5: Vérifier la lecture réelle depuis l'app**

C'est la vérification annoncée dans la spec : la lecture doit fonctionner depuis un process GUI, pas seulement depuis un terminal. Ajouter temporairement dans `AppDelegate.applicationDidFinishLaunching` :

```swift
DiagnosticLog.append("env probe: \(String(describing: ProcessEnvironment.markers(pid: getpid())))")
```

Run: `./Scripts/build-app.sh --install`
Expected: la trace montre `Markers(isClaude: false, projectDirectory: nil)` — non nil. Un `nil` signifierait que `sysctl` est refusé au process GUI et déclencherait le repli décrit dans la spec.

Retirer la ligne de sonde avant de committer.

- [ ] **Step 6: Commit**

```bash
git add Claudy/Services/ProcessEnvironment.swift ClaudyTests/ProcessEnvironmentTests.swift
git commit -m "$(cat <<'EOF'
feat: read Claude Code markers from a process environment

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: ProcessTable — arbre des process

**Files:**
- Create: `Claudy/Services/ProcessTable.swift`
- Test: `ClaudyTests/ProcessTableTests.swift`

**Interfaces:**
- Consumes: rien
- Produces:
  - `struct RunningProcess: Equatable { let pid: pid_t; let parent: pid_t; let startedAt: Date; let arguments: String }`
  - `struct ProcessTable { let processes: [pid_t: RunningProcess] }`
  - `static func ProcessTable.parse(_ output: String) -> ProcessTable`
  - `static func ProcessTable.load() -> ProcessTable?`
  - `func ProcessTable.ancestors(of pid: pid_t) -> [RunningProcess]`
  - `func ProcessTable.claudeSessionRoot(of pid: pid_t) -> RunningProcess?`
  - `static func ProcessTable.isClaudeBinary(_ arguments: String) -> Bool`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `ClaudyTests/ProcessTableTests.swift` :

```swift
import XCTest
@testable import Claudy

final class ProcessTableTests: XCTestCase {

    /// Real `ps -Ao pid=,ppid=,lstart=,args=` output, captured on 2026-09-03.
    private let output = """
      46694 46686 Thu Sep  3 19:31:02 2026 /opt/homebrew/bin/python3 -m http.server 4000
      46686  8859 Thu Sep  3 19:31:02 2026 /bin/zsh -c source /Users/x/.claude/shell-snapshots/snap.sh
       8859  6172 Wed Sep  2 09:12:44 2026 /Users/x/.vscode/extensions/anthropic.claude-code-2.1.257-darwin-arm64/resources/native-binary/claude --output-format stream-json
       6172 21476 Wed Sep  2 09:12:40 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Code Helper (Plugin)
      21476     1 Wed Sep  2 09:12:31 2026 /Applications/Visual Studio Code.app/Contents/MacOS/Code
       5771 49296 Thu Sep  3 19:10:26 2026 next-server (v16.2.12)
    """

    func testParsesPidParentAndArguments() {
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.processes.count, 6)
        XCTAssertEqual(table.processes[46694]?.parent, 46686)
        XCTAssertEqual(table.processes[46694]?.arguments, "/opt/homebrew/bin/python3 -m http.server 4000")
    }

    /// `lstart` is five whitespace-separated tokens with a padded day number; the argument
    /// string starts only after them.
    func testParsesStartDate() {
        let table = ProcessTable.parse(output)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone.current, from: try! XCTUnwrap(table.processes[46694]?.startedAt)
        )
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 19)
        XCTAssertEqual(components.minute, 31)
    }

    func testWalksAncestorsUpToTheRoot() {
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.ancestors(of: 46694).map(\.pid), [46686, 8859, 6172, 21476])
    }

    func testFindsClaudeSessionRoot() {
        let table = ProcessTable.parse(output)
        XCTAssertEqual(table.claudeSessionRoot(of: 46694)?.pid, 8859)
    }

    func testProcessWithoutClaudeAncestorHasNoSessionRoot() {
        let table = ProcessTable.parse(output)
        XCTAssertNil(table.claudeSessionRoot(of: 5771))
    }

    func testRecognisesClaudeBinaryPaths() {
        XCTAssertTrue(ProcessTable.isClaudeBinary("/Users/x/.claude/local/claude"))
        XCTAssertTrue(ProcessTable.isClaudeBinary("/Users/x/.vscode/extensions/anthropic.claude-code-2.1.257/native-binary/claude --debug"))
        XCTAssertTrue(ProcessTable.isClaudeBinary("/usr/local/lib/node_modules/@anthropic-ai/claude-code/cli.js"))
        XCTAssertFalse(ProcessTable.isClaudeBinary("/usr/bin/claudia"))
        XCTAssertFalse(ProcessTable.isClaudeBinary("/bin/zsh -c echo claude"))
    }

    /// A malformed table must not hang the scan.
    func testCyclicParentDoesNotLoop() {
        let cyclic = """
          10 11 Thu Sep  3 19:31:02 2026 /bin/a
          11 10 Thu Sep  3 19:31:02 2026 /bin/b
        """
        XCTAssertLessThan(ProcessTable.parse(cyclic).ancestors(of: 10).count, 70)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/ProcessTableTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'ProcessTable' in scope`.

- [ ] **Step 3: Implémenter**

Créer `Claudy/Services/ProcessTable.swift` :

```swift
import Foundation

struct RunningProcess: Equatable {
    let pid: pid_t
    let parent: pid_t
    /// Start time, which turns a reusable PID into a stable identity.
    let startedAt: Date
    let arguments: String
}

/// A snapshot of the process tree, read in one `ps` pass.
///
/// Attribution does not depend on this table — the environment carries that. The tree serves
/// one purpose: knowing which Claude session is still alive, so the reaper never kills it.
struct ProcessTable {
    let processes: [pid_t: RunningProcess]

    private static let maximumDepth = 64

    private static let executable = "/bin/ps"
    private static let arguments = ["-Ao", "pid=,ppid=,lstart=,args="]
    private static let timeout: TimeInterval = 4

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        return formatter
    }()

    static func load() -> ProcessTable? {
        guard let output = Subprocess.run(executable, arguments, timeout: timeout) else {
            DiagnosticLog.append("ports: ps failed")
            return nil
        }
        return parse(output)
    }

    /// `lstart` is five whitespace-separated tokens (`Thu Sep  3 19:31:02 2026`), so the split
    /// is positional: pid, ppid, five date tokens, then the argument string verbatim.
    static func parse(_ output: String) -> ProcessTable {
        var processes: [pid_t: RunningProcess] = [:]

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            var scanner = line.drop { $0 == " " }
            guard let pid = scanner.takeInteger(), let parent = scanner.takeInteger() else { continue }

            var dateTokens: [String] = []
            for _ in 0..<5 {
                guard let token = scanner.takeToken() else { break }
                dateTokens.append(token)
            }
            guard dateTokens.count == 5,
                  let startedAt = dateFormatter.date(from: dateTokens.joined(separator: " "))
            else { continue }

            let arguments = String(scanner.drop { $0 == " " })
            processes[pid] = RunningProcess(pid: pid, parent: parent, startedAt: startedAt, arguments: arguments)
        }

        return ProcessTable(processes: processes)
    }

    /// Ancestors from the closest parent upward. Depth-capped: a malformed table must never
    /// spin the scan.
    func ancestors(of pid: pid_t) -> [RunningProcess] {
        var found: [RunningProcess] = []
        var seen: Set<pid_t> = [pid]
        var current = processes[pid]?.parent

        while let parent = current, parent > 1, found.count < Self.maximumDepth, !seen.contains(parent) {
            guard let process = processes[parent] else { break }
            found.append(process)
            seen.insert(parent)
            current = process.parent
        }
        return found
    }

    /// The live Claude session a process belongs to, when there is one.
    func claudeSessionRoot(of pid: pid_t) -> RunningProcess? {
        ancestors(of: pid).first { Self.isClaudeBinary($0.arguments) }
    }

    static func isClaudeBinary(_ arguments: String) -> Bool {
        let path = arguments.split(separator: " ", maxSplits: 1).first.map(String.init) ?? arguments
        if (path as NSString).lastPathComponent == "claude" { return true }
        return path.contains("anthropic.claude-code") || path.contains("@anthropic-ai/claude-code")
    }
}

private extension Substring {
    mutating func takeToken() -> String? {
        self = drop { $0 == " " }
        guard let end = firstIndex(of: " ") else {
            guard !isEmpty else { return nil }
            defer { self = self[endIndex...] }
            return String(self)
        }
        let token = String(self[startIndex..<end])
        self = self[end...]
        return token
    }

    mutating func takeInteger() -> pid_t? {
        guard let token = takeToken(), let value = pid_t(token) else { return nil }
        return value
    }
}
```

Créer aussi `Claudy/Services/Subprocess.swift`, l'exécution partagée dont dépendent `ProcessTable` et `PortScanner` :

```swift
import Foundation

/// Runs a short-lived command and returns its standard output.
///
/// Absolute executable path and an argument array only: no shell is ever involved, so no
/// string built here can be reinterpreted as a command. The timeout matters as much as the
/// result — a scan that hangs would freeze the widget's refresh.
enum Subprocess {
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        do { try process.run() } catch {
            DiagnosticLog.append("subprocess: could not launch \(executable)")
            return nil
        }

        var data = Data()
        let reader = DispatchQueue(label: "com.claudy.subprocess.read")
        let finished = DispatchSemaphore(value: 0)
        reader.async {
            data = (try? output.fileHandleForReading.readToEnd()) ?? Data()
            finished.signal()
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            DiagnosticLog.append("subprocess: \(executable) timed out")
            return nil
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            DiagnosticLog.append("subprocess: \(executable) exited \(process.terminationStatus)")
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/ProcessTableTests 2>&1 | tail -20`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Claudy/Services/ProcessTable.swift Claudy/Services/Subprocess.swift ClaudyTests/ProcessTableTests.swift
git commit -m "$(cat <<'EOF'
feat: snapshot the process tree to locate live Claude sessions

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: PortScanner — listeners et attribution

**Files:**
- Create: `Claudy/Models/PortModels.swift`
- Create: `Claudy/Services/PortScanner.swift`
- Test: `ClaudyTests/PortScannerTests.swift`

**Interfaces:**
- Consumes: `ProcessEnvironment.Markers`, `ProcessTable`, `Subprocess`
- Produces:
  - `struct Listener: Equatable { let pid: pid_t; let command: String; let port: Int; let address: String }`
  - `enum PortAttribution: Equatable { case live, orphan }`
  - `struct ListeningPort: Identifiable, Equatable { let id: String; let pid: pid_t; let port: Int; let command: String; let projectName: String?; let startedAt: Date; let attribution: PortAttribution; let sessionRootPID: pid_t? }`
  - `enum PortScanState: Equatable { case scanning, ready([ListeningPort]), unavailable(String) }`
  - `static func PortScanner.parseListeners(_ output: String) -> [Listener]`
  - `static func PortScanner.isDenied(command: String) -> Bool`
  - `static func PortScanner.attribute(listeners:table:markers:) -> [ListeningPort]`
  - `func PortScanner.scan() -> PortScanState`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `ClaudyTests/PortScannerTests.swift` :

```swift
import XCTest
@testable import Claudy

final class PortScannerTests: XCTestCase {

    /// Real `lsof -nP -iTCP -sTCP:LISTEN -a -u <uid> -F pcn` output. lsof emits fields that
    /// were never asked for — `f` here — and the parser must ignore them.
    private let output = """
    p46694
    cPython
    f3
    n127.0.0.1:4000
    p95778
    cbun
    f22
    n127.0.0.1:37701
    p40964
    cOrbStack
    f11
    n*:3001
    p5771
    cnode
    f18
    n[::1]:3000
    """

    func testParsesPidCommandAndPort() {
        let listeners = PortScanner.parseListeners(output)
        XCTAssertEqual(listeners.count, 4)
        XCTAssertEqual(listeners[0], Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1"))
    }

    func testParsesWildcardAndIPv6Addresses() {
        let listeners = PortScanner.parseListeners(output)
        XCTAssertEqual(listeners[2].port, 3001)
        XCTAssertEqual(listeners[2].address, "*")
        XCTAssertEqual(listeners[3].port, 3000)
        XCTAssertEqual(listeners[3].address, "[::1]")
    }

    func testDeniesContainerRuntimes() {
        XCTAssertTrue(PortScanner.isDenied(command: "OrbStack"))
        XCTAssertTrue(PortScanner.isDenied(command: "com.docker.backend"))
        XCTAssertTrue(PortScanner.isDenied(command: "Docker"))
        XCTAssertFalse(PortScanner.isDenied(command: "node"))
    }

    private func table(_ processes: [RunningProcess]) -> ProcessTable {
        ProcessTable(processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }))
    }

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    func testAttributesLivePortWhenClaudeAncestorIsAlive() {
        let ports = PortScanner.attribute(
            listeners: [Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1")],
            table: table([
                RunningProcess(pid: 46694, parent: 8859, startedAt: epoch, arguments: "python3 -m http.server"),
                RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude"),
            ]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: "/Users/x/Dev/Surikat") }
        )
        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].attribution, .live)
        XCTAssertEqual(ports[0].sessionRootPID, 8859)
        XCTAssertEqual(ports[0].projectName, "Surikat")
    }

    func testAttributesOrphanWhenClaudeAncestorIsGone() {
        let ports = PortScanner.attribute(
            listeners: [Listener(pid: 95778, command: "bun", port: 37701, address: "127.0.0.1")],
            table: table([RunningProcess(pid: 95778, parent: 1, startedAt: epoch, arguments: "bun worker")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil) }
        )
        XCTAssertEqual(ports[0].attribution, .orphan)
        XCTAssertNil(ports[0].sessionRootPID)
    }

    func testDropsPortsWithoutMarkers() {
        let ports = PortScanner.attribute(
            listeners: [Listener(pid: 5771, command: "node", port: 3000, address: "*")],
            table: table([RunningProcess(pid: 5771, parent: 1, startedAt: epoch, arguments: "next-server")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: false, projectDirectory: nil) }
        )
        XCTAssertTrue(ports.isEmpty)
    }

    /// A container runtime publishes ports on behalf of everything it hosts: killing it would
    /// take the whole runtime down, so it is never attributed whatever its environment says.
    func testDropsDeniedCommandsEvenWithMarkers() {
        let ports = PortScanner.attribute(
            listeners: [Listener(pid: 40964, command: "OrbStack", port: 3001, address: "*")],
            table: table([RunningProcess(pid: 40964, parent: 1, startedAt: epoch, arguments: "OrbStack")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil) }
        )
        XCTAssertTrue(ports.isEmpty)
    }

    func testIdentityCombinesPidAndPort() {
        let ports = PortScanner.attribute(
            listeners: [Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1")],
            table: table([RunningProcess(pid: 46694, parent: 1, startedAt: epoch, arguments: "python3")]),
            markers: { _ in ProcessEnvironment.Markers(isClaude: true, projectDirectory: nil) }
        )
        XCTAssertEqual(ports[0].id, "46694-4000")
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortScannerTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PortScanner' in scope`.

- [ ] **Step 3: Implémenter les modèles**

Créer `Claudy/Models/PortModels.swift` :

```swift
import Foundation

/// One TCP socket in the LISTEN state, as reported by lsof.
struct Listener: Equatable {
    let pid: pid_t
    let command: String
    let port: Int
    let address: String
}

enum PortAttribution: Equatable {
    /// A Claude session that is still running owns this port.
    case live
    /// Claude launched it, and the session that did is gone. The reason this tab exists.
    case orphan
}

struct ListeningPort: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let port: Int
    let command: String
    let projectName: String?
    let startedAt: Date
    let attribution: PortAttribution
    let sessionRootPID: pid_t?
}

enum PortScanState: Equatable {
    case scanning
    case ready([ListeningPort])
    /// The scan could not run at all; the string is shown to the user as the reason.
    case unavailable(String)
}
```

- [ ] **Step 4: Implémenter le scanner**

Créer `Claudy/Services/PortScanner.swift` :

```swift
import Foundation

/// Lists the TCP ports Claude Code is holding open on this machine.
///
/// Attribution comes from the process environment, never from the process tree: an orphaned
/// server has no Claude ancestor left, yet it is exactly the one worth killing. The tree only
/// answers a second question — is the owning session still alive.
struct PortScanner {

    /// A container runtime publishes ports for everything it hosts. Killing it would take the
    /// runtime down with the container, so it is never attributed, whatever its environment.
    private static let deniedCommands = ["orbstack", "docker", "com.docker.backend"]

    private static let executable = "/usr/sbin/lsof"
    private static let timeout: TimeInterval = 6

    private static var arguments: [String] {
        ["-nP", "-iTCP", "-sTCP:LISTEN", "-a", "-u", String(getuid()), "-F", "pcn"]
    }

    func scan() -> PortScanState {
        guard let output = Subprocess.run(Self.executable, Self.arguments, timeout: Self.timeout) else {
            return .unavailable("lsof n'a pas répondu")
        }
        guard let table = ProcessTable.load() else {
            return .unavailable("ps n'a pas répondu")
        }
        let ports = Self.attribute(
            listeners: Self.parseListeners(output),
            table: table,
            markers: { ProcessEnvironment.markers(pid: $0) }
        )
        return .ready(ports.sorted { $0.port < $1.port })
    }

    /// lsof's field output: one field per line, prefixed by its letter. `p` opens a process
    /// block, `c` names it, `n` describes one socket. Any other field — `f` among them — is
    /// ignored rather than assumed absent.
    static func parseListeners(_ output: String) -> [Listener] {
        var listeners: [Listener] = []
        var pid: pid_t?
        var command = ""

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let value = String(line.dropFirst())
            switch line.first {
            case "p": pid = pid_t(value)
            case "c": command = value
            case "n":
                guard let pid, let (address, port) = splitEndpoint(value) else { continue }
                listeners.append(Listener(pid: pid, command: command, port: port, address: address))
            default: continue
            }
        }
        return listeners
    }

    /// `127.0.0.1:4000`, `*:3001` and `[::1]:3000` all split at the last colon.
    private static func splitEndpoint(_ endpoint: String) -> (String, Int)? {
        guard let separator = endpoint.lastIndex(of: ":"),
              let port = Int(endpoint[endpoint.index(after: separator)...])
        else { return nil }
        return (String(endpoint[..<separator]), port)
    }

    static func isDenied(command: String) -> Bool {
        let lowered = command.lowercased()
        return deniedCommands.contains { lowered.contains($0) }
    }

    /// `markers` is injected so attribution can be tested without any live process.
    static func attribute(
        listeners: [Listener],
        table: ProcessTable,
        markers: (pid_t) -> ProcessEnvironment.Markers?
    ) -> [ListeningPort] {
        listeners.compactMap { listener in
            guard !isDenied(command: listener.command),
                  let marker = markers(listener.pid), marker.isClaude,
                  let process = table.processes[listener.pid]
            else { return nil }

            let root = table.claudeSessionRoot(of: listener.pid)
            return ListeningPort(
                id: "\(listener.pid)-\(listener.port)",
                pid: listener.pid,
                port: listener.port,
                command: listener.command,
                projectName: marker.projectDirectory.map { ($0 as NSString).lastPathComponent },
                startedAt: process.startedAt,
                attribution: root == nil ? .orphan : .live,
                sessionRootPID: root?.pid
            )
        }
    }
}
```

- [ ] **Step 5: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortScannerTests 2>&1 | tail -20`
Expected: PASS, 8 tests.

- [ ] **Step 6: Commit**

```bash
git add Claudy/Models/PortModels.swift Claudy/Services/PortScanner.swift ClaudyTests/PortScannerTests.swift
git commit -m "$(cat <<'EOF'
feat: attribute listening ports to Claude Code by process environment

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: PortReaper — kill sous garde-fous

**Files:**
- Create: `Claudy/Services/PortReaper.swift`
- Test: `ClaudyTests/PortReaperTests.swift`

**Interfaces:**
- Consumes: `ListeningPort`, `ProcessTable`
- Produces:
  - `protocol SignalSending { func send(_ signal: Int32, to pid: pid_t) -> Bool; func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool; func processGroup(of pid: pid_t) -> pid_t?; func isRunning(_ pid: pid_t) -> Bool }`
  - `enum KillRefusal: Error, Equatable { case identityChanged, protectedProcess, liveClaudeSession, systemRefused, survivedKill }`
  - `struct PortReaper { init(signals: SignalSending, ownPID: pid_t); func kill(_ port: ListeningPort, table: ProcessTable) -> Result<Void, KillRefusal> }`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `ClaudyTests/PortReaperTests.swift` :

```swift
import XCTest
@testable import Claudy

private final class FakeSignals: SignalSending {
    var alive: Set<pid_t>
    var groups: [pid_t: pid_t]
    var sent: [(Int32, pid_t)] = []
    var diesOnTerm: Bool

    init(alive: Set<pid_t>, groups: [pid_t: pid_t] = [:], diesOnTerm: Bool = true) {
        self.alive = alive
        self.groups = groups
        self.diesOnTerm = diesOnTerm
    }

    func send(_ signal: Int32, to pid: pid_t) -> Bool {
        sent.append((signal, pid))
        if signal == SIGKILL || (signal == SIGTERM && diesOnTerm) { alive.remove(pid) }
        return true
    }

    func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool {
        sent.append((signal, -pgid))
        if signal == SIGKILL || (signal == SIGTERM && diesOnTerm) {
            alive = alive.filter { groups[$0] != pgid }
        }
        return true
    }

    func processGroup(of pid: pid_t) -> pid_t? { groups[pid] }
    func isRunning(_ pid: pid_t) -> Bool { alive.contains(pid) }
}

final class PortReaperTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    private func port(pid: pid_t, attribution: PortAttribution = .orphan, session: pid_t? = nil) -> ListeningPort {
        ListeningPort(id: "\(pid)-4000", pid: pid, port: 4000, command: "Python",
                      projectName: nil, startedAt: epoch, attribution: attribution, sessionRootPID: session)
    }

    private func table(_ processes: [RunningProcess]) -> ProcessTable {
        ProcessTable(processes: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) }))
    }

    func testTerminatesTheProcessGroup() {
        let signals = FakeSignals(alive: [500], groups: [500: 500])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 500),
                                 table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch, arguments: "python3")]))
        XCTAssertEqual(result, .success(()))
        XCTAssertEqual(signals.sent.map(\.0), [SIGTERM])
    }

    func testEscalatesToKillWhenTermIsIgnored() {
        let signals = FakeSignals(alive: [500], groups: [500: 500], diesOnTerm: false)
        let reaper = PortReaper(signals: signals, ownPID: 99)
        _ = reaper.kill(port(pid: 500),
                        table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch, arguments: "python3")]))
        XCTAssertEqual(signals.sent.map(\.0), [SIGTERM, SIGKILL])
    }

    /// Between the render and the click, the process may have died and its PID been reissued
    /// to something else. The start time is what tells the two apart.
    func testRefusesWhenStartTimeNoLongerMatches() {
        let signals = FakeSignals(alive: [500], groups: [500: 500])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            port(pid: 500),
            table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch.addingTimeInterval(60), arguments: "python3")])
        )
        XCTAssertEqual(result, .failure(.identityChanged))
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesToKillItself() {
        let signals = FakeSignals(alive: [99], groups: [99: 99])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 99),
                                 table: table([RunningProcess(pid: 99, parent: 1, startedAt: epoch, arguments: "Claudy")]))
        XCTAssertEqual(result, .failure(.protectedProcess))
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesToKillItsOwnAncestor() {
        let signals = FakeSignals(alive: [42], groups: [42: 42])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            port(pid: 42),
            table: table([
                RunningProcess(pid: 99, parent: 42, startedAt: epoch, arguments: "Claudy"),
                RunningProcess(pid: 42, parent: 1, startedAt: epoch, arguments: "launcher"),
            ])
        )
        XCTAssertEqual(result, .failure(.protectedProcess))
    }

    /// Killing the port would be one thing; killing the Claude session that owns it is another.
    func testRefusesToKillALiveClaudeSessionRoot() {
        let signals = FakeSignals(alive: [8859], groups: [8859: 8859])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(
            port(pid: 8859, attribution: .live, session: 8859),
            table: table([RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude")])
        )
        XCTAssertEqual(result, .failure(.liveClaudeSession))
        XCTAssertTrue(signals.sent.isEmpty)
    }

    func testRefusesPidOne() {
        let signals = FakeSignals(alive: [1], groups: [1: 1])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        let result = reaper.kill(port(pid: 1),
                                 table: table([RunningProcess(pid: 1, parent: 0, startedAt: epoch, arguments: "launchd")]))
        XCTAssertEqual(result, .failure(.protectedProcess))
    }

    /// A process group shared with Claudy itself must never be signalled as a group.
    func testFallsBackToSinglePidWhenGroupIsShared() {
        let signals = FakeSignals(alive: [500], groups: [500: 99, 99: 99])
        let reaper = PortReaper(signals: signals, ownPID: 99)
        _ = reaper.kill(port(pid: 500),
                        table: table([RunningProcess(pid: 500, parent: 1, startedAt: epoch, arguments: "python3")]))
        XCTAssertEqual(signals.sent.first?.1, 500)
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortReaperTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PortReaper' in scope`.

- [ ] **Step 3: Implémenter**

Créer `Claudy/Services/PortReaper.swift` :

```swift
import Foundation

/// The signalling side effects, behind a protocol so the guardrails can be tested without
/// ever signalling a real process.
protocol SignalSending {
    func send(_ signal: Int32, to pid: pid_t) -> Bool
    func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool
    func processGroup(of pid: pid_t) -> pid_t?
    func isRunning(_ pid: pid_t) -> Bool
}

struct SystemSignals: SignalSending {
    func send(_ signal: Int32, to pid: pid_t) -> Bool { Foundation.kill(pid, signal) == 0 }
    func sendToGroup(_ signal: Int32, pgid: pid_t) -> Bool { killpg(pgid, signal) == 0 }
    func processGroup(of pid: pid_t) -> pid_t? {
        let group = getpgid(pid)
        return group == -1 ? nil : group
    }
    func isRunning(_ pid: pid_t) -> Bool { Foundation.kill(pid, 0) == 0 || errno == EPERM }
}

enum KillRefusal: Error, Equatable {
    case identityChanged
    case protectedProcess
    case liveClaudeSession
    case systemRefused
    case survivedKill
}

/// Kills a port's process, or refuses and says why.
///
/// Every refusal here is a case where killing would be worse than leaving the port open:
/// signalling the wrong process after a PID reuse, taking down Claudy, or taking down the
/// Claude session the user is currently talking to.
struct PortReaper {
    private let signals: SignalSending
    private let ownPID: pid_t
    private let graceSeconds: TimeInterval = 3
    private let pollSeconds: TimeInterval = 0.1

    init(signals: SignalSending = SystemSignals(), ownPID: pid_t = getpid()) {
        self.signals = signals
        self.ownPID = ownPID
    }

    func kill(_ port: ListeningPort, table: ProcessTable) -> Result<Void, KillRefusal> {
        guard port.pid > 1, port.pid != ownPID else { return .failure(.protectedProcess) }

        guard let process = table.processes[port.pid] else { return .failure(.identityChanged) }
        guard process.startedAt == port.startedAt else { return .failure(.identityChanged) }

        if table.ancestors(of: ownPID).contains(where: { $0.pid == port.pid }) {
            return .failure(.protectedProcess)
        }
        if ProcessTable.isClaudeBinary(process.arguments), signals.isRunning(port.pid) {
            return .failure(.liveClaudeSession)
        }

        guard terminate(port.pid, using: SIGTERM) else { return .failure(.systemRefused) }
        if waitForExit(port.pid) { return .success(()) }

        guard terminate(port.pid, using: SIGKILL) else { return .failure(.systemRefused) }
        return waitForExit(port.pid) ? .success(()) : .failure(.survivedKill)
    }

    /// A dev server is usually a tree — the group carries the children with it. The group is
    /// only signalled when it is neither Claudy's own nor launchd's.
    private func terminate(_ pid: pid_t, using signal: Int32) -> Bool {
        let ownGroup = signals.processGroup(of: ownPID)
        if let group = signals.processGroup(of: pid), group > 1, group != ownGroup {
            return signals.sendToGroup(signal, pgid: group)
        }
        return signals.send(signal, to: pid)
    }

    private func waitForExit(_ pid: pid_t) -> Bool {
        let deadline = Date().addingTimeInterval(graceSeconds)
        while Date() < deadline {
            if !signals.isRunning(pid) { return true }
            Thread.sleep(forTimeInterval: pollSeconds)
        }
        return !signals.isRunning(pid)
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortReaperTests 2>&1 | tail -20`
Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Claudy/Services/PortReaper.swift ClaudyTests/PortReaperTests.swift
git commit -m "$(cat <<'EOF'
feat: kill a Claude port behind identity and protection guardrails

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: PortsViewModel — état et cadence

**Files:**
- Create: `Claudy/ViewModels/PortsViewModel.swift`
- Test: `ClaudyTests/PortsViewModelTests.swift`

**Interfaces:**
- Consumes: `PortScanState`, `PortScanner`, `PortReaper`, `ProcessTable`
- Produces:
  - `protocol PortScanning { func scan() -> PortScanState }` (conformance ajoutée à `PortScanner`)
  - `@MainActor final class PortsViewModel: ObservableObject` avec `@Published private(set) var state: PortScanState`, `@Published private(set) var failures: [String: String]`, `var orphanCount: Int`, `func refresh() async`, `func kill(_ port: ListeningPort) async`, `func setVisible(_ isVisible: Bool)`
  - `static func PortsViewModel.age(since: Date, now: Date) -> String`

- [ ] **Step 1: Écrire les tests qui échouent**

Créer `ClaudyTests/PortsViewModelTests.swift` :

```swift
import XCTest
@testable import Claudy

private struct StubScanner: PortScanning {
    let result: PortScanState
    func scan() -> PortScanState { result }
}

@MainActor
final class PortsViewModelTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_788_000_000)

    private func port(_ pid: pid_t, _ attribution: PortAttribution) -> ListeningPort {
        ListeningPort(id: "\(pid)-4000", pid: pid, port: 4000, command: "Python",
                      projectName: "Surikat", startedAt: epoch, attribution: attribution, sessionRootPID: nil)
    }

    func testPublishesScannedPorts() async {
        let model = PortsViewModel(scanner: StubScanner(result: .ready([port(500, .orphan)])))
        await model.refresh()
        XCTAssertEqual(model.state, .ready([port(500, .orphan)]))
    }

    func testCountsOnlyOrphans() async {
        let model = PortsViewModel(
            scanner: StubScanner(result: .ready([port(500, .orphan), port(501, .live)]))
        )
        await model.refresh()
        XCTAssertEqual(model.orphanCount, 1)
    }

    func testUnavailableScanIsPublishedAsIs() async {
        let model = PortsViewModel(scanner: StubScanner(result: .unavailable("lsof n'a pas répondu")))
        await model.refresh()
        XCTAssertEqual(model.state, .unavailable("lsof n'a pas répondu"))
    }

    func testAgeReadsInTheLargestUsefulUnit() {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-45), now: now), "45 s")
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-3 * 60), now: now), "3 min")
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-5 * 3600), now: now), "5 h")
        XCTAssertEqual(PortsViewModel.age(since: now.addingTimeInterval(-2 * 86400), now: now), "2 j")
    }
}
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortsViewModelTests 2>&1 | tail -20`
Expected: FAIL — `cannot find 'PortsViewModel' in scope`.

- [ ] **Step 3: Implémenter**

Ajouter la conformance en bas de `Claudy/Services/PortScanner.swift` :

```swift
protocol PortScanning {
    func scan() -> PortScanState
}

extension PortScanner: PortScanning {}
```

Créer `Claudy/ViewModels/PortsViewModel.swift` :

```swift
import Foundation
import SwiftUI

/// Drives the Ports tab: what is open, how old it is, and what happened to a kill.
///
/// The scan runs off the main actor — `lsof` and `ps` are cheap but not free, and the widget's
/// gauges must never wait on them. The cadence is slower in the background than on screen:
/// the only thing a hidden tab owes the user is a correct badge.
@MainActor
final class PortsViewModel: ObservableObject {

    @Published private(set) var state: PortScanState = .scanning
    /// Kill failures, keyed by port id, shown inline on the row that failed.
    @Published private(set) var failures: [String: String] = [:]

    private let scanner: PortScanning
    private let reaper: PortReaper
    private var timer: Timer?
    private var isVisible = false

    private let visibleInterval: TimeInterval = 5
    private let backgroundInterval: TimeInterval = 30

    init(scanner: PortScanning = PortScanner(), reaper: PortReaper = PortReaper()) {
        self.scanner = scanner
        self.reaper = reaper
    }

    var ports: [ListeningPort] {
        if case .ready(let ports) = state { return ports }
        return []
    }

    var orphanCount: Int {
        ports.filter { $0.attribution == .orphan }.count
    }

    func start() {
        schedule(interval: backgroundInterval)
        Task { await refresh() }
    }

    func setVisible(_ isVisible: Bool) {
        self.isVisible = isVisible
        schedule(interval: isVisible ? visibleInterval : backgroundInterval)
        if isVisible { Task { await refresh() } }
    }

    func refresh() async {
        let scanner = self.scanner
        let scanned = await Task.detached(priority: .utility) { scanner.scan() }.value
        state = scanned
    }

    func kill(_ port: ListeningPort) async {
        let reaper = self.reaper
        let outcome = await Task.detached(priority: .userInitiated) { () -> Result<Void, KillRefusal> in
            guard let table = ProcessTable.load() else { return .failure(.identityChanged) }
            return reaper.kill(port, table: table)
        }.value

        switch outcome {
        case .success:
            failures[port.id] = nil
        case .failure(let refusal):
            failures[port.id] = Self.explain(refusal)
        }
        await refresh()
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private static func explain(_ refusal: KillRefusal) -> String {
        switch refusal {
        case .identityChanged: "le process a changé, rien n'a été tué"
        case .protectedProcess: "process protégé"
        case .liveClaudeSession: "session Claude en cours"
        case .systemRefused: "refusé par le système"
        case .survivedKill: "toujours vivant après SIGKILL"
        }
    }

    /// Age in the largest unit that still reads at a glance.
    static func age(since date: Date, now: Date = Date()) -> String {
        let seconds = Int(now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "\(max(seconds, 0)) s"
        case ..<3600: return "\(seconds / 60) min"
        case ..<86400: return "\(seconds / 3600) h"
        default: return "\(seconds / 86400) j"
        }
    }
}
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortsViewModelTests 2>&1 | tail -20`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add Claudy/ViewModels/PortsViewModel.swift Claudy/Services/PortScanner.swift ClaudyTests/PortsViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: drive the ports tab state and scan cadence

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: TabSwitcher et bascule dans FullView

**Files:**
- Create: `Claudy/Views/Components/TabSwitcher.swift`
- Modify: `Claudy/Theme/Theme.swift`
- Modify: `Claudy/Views/FullView.swift:12-43`
- Modify: `Claudy/ViewModels/UsageViewModel.swift`

**Interfaces:**
- Consumes: `PortsViewModel.orphanCount`
- Produces:
  - `enum CardTab: String, CaseIterable { case usage, ports }`
  - `struct TabSwitcher: View { init(selection: Binding<CardTab>, badge: Int) }`
  - `UsageViewModel.tab: CardTab` (publié)

- [ ] **Step 1: Ajouter les métriques au thème**

Dans `Claudy/Theme/Theme.swift`, dans `enum Metric`, après `padding` :

```swift
        /// Height of the usage/ports switch, and the corner of its selected segment.
        static let tabHeight: CGFloat = 22
        static let tabCorner: CGFloat = 7
```

- [ ] **Step 2: Ajouter l'onglet au view model**

Dans `Claudy/ViewModels/UsageViewModel.swift`, ajouter la propriété publiée près des autres `@Published` :

```swift
    /// Which face of the card is showing. Usage is the product; ports is an annex.
    @Published var tab: CardTab = .usage
```

- [ ] **Step 3: Écrire le sélecteur**

Créer `Claudy/Views/Components/TabSwitcher.swift` :

```swift
import SwiftUI

enum CardTab: String, CaseIterable {
    case usage, ports
}

/// Two quiet segments in the card header. The badge is the only thing allowed to raise its
/// voice, and only when something is actually left running.
struct TabSwitcher: View {
    @Binding var selection: CardTab
    let badge: Int

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 2) {
            ForEach(CardTab.allCases, id: \.self) { tab in
                segment(tab)
            }
        }
        .padding(2)
        .background(Capsule().fill(.primary.opacity(0.06)))
    }

    private func segment(_ tab: CardTab) -> some View {
        let isSelected = selection == tab

        return HStack(spacing: 4) {
            Text(tab.rawValue)
                .font(Theme.Font.label(9.5, .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.primary.opacity(isSelected ? 0.9 : 0.45))

            if tab == .ports, badge > 0 {
                Text("\(badge)")
                    .font(Theme.Font.value(8.5, .bold))
                    .foregroundStyle(Theme.Accent.amber.color)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Theme.Accent.amber.color.opacity(0.18)))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: Theme.Metric.tabHeight)
        .background {
            if isSelected {
                Capsule()
                    .fill(.primary.opacity(0.10))
                    .matchedGeometryEffect(id: "tab", in: indicator)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(Theme.Motion.mode) { selection = tab }
        }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
```

- [ ] **Step 4: Brancher la bascule dans FullView**

Dans `Claudy/Views/FullView.swift`, ajouter le view model des ports en propriété d'environnement, sous la ligne `@EnvironmentObject private var viewModel: UsageViewModel` :

```swift
    @EnvironmentObject private var portsViewModel: PortsViewModel
```

Remplacer le corps de `body` (le `VStack` actuel, lignes 12-43) par :

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            header
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleMode() }

            TabSwitcher(selection: $viewModel.tab, badge: portsViewModel.orphanCount)

            switch viewModel.tab {
            case .usage: usageTab
            case .ports: PortsView()
            }
        }
        .padding(.horizontal, Theme.Metric.padding)
        .padding(.vertical, 14)
        .frame(width: Theme.Metric.fullWidth)
        .onChange(of: viewModel.tab) { tab in
            portsViewModel.setVisible(tab == .ports)
        }
    }

    /// The card's original content, unchanged: the tab switch only chooses between this and
    /// the ports annex.
    private var usageTab: some View {
        VStack(alignment: .leading, spacing: 11) {
            sessionBlock
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleMode() }
                .help("Click for minimal mode")

            HStack(spacing: 9) {
                StatColumn(window: snapshot.weekly)
                StatColumn(window: snapshot.sonnet)
            }

            totals
            hairline
            chart
            hairline
            DetailsSection()
            hairline

            FooterView(
                sessionCount: snapshot.sessionCount,
                updatedAt: snapshot.updatedAt,
                isRefreshing: viewModel.isRefreshing,
                onRefresh: { Task { await viewModel.refresh(userInitiated: true) } }
            )
        }
    }
```

Note : `onChange(of:perform:)` à un argument est la forme valide pour la cible macOS 13 ; la forme à deux arguments exige macOS 14.

- [ ] **Step 5: Injecter le view model dans l'app**

Dans `Claudy/App/AppDelegate.swift`, là où `UsageViewModel` est créé et injecté par `.environmentObject(...)`, créer et injecter également :

```swift
    private let portsViewModel = PortsViewModel()
```

puis, à la suite du `.environmentObject(usageViewModel)` existant :

```swift
            .environmentObject(portsViewModel)
```

et démarrer la cadence de fond juste après l'affichage de la fenêtre :

```swift
        portsViewModel.start()
```

- [ ] **Step 6: Compiler et vérifier visuellement**

Run: `xcodebuild build -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`. `PortsView` n'existe pas encore — créer un fichier provisoire `Claudy/Views/PortsView.swift` avec `struct PortsView: View { var body: some View { Text("ports") } }`, remplacé intégralement en Task 8.

- [ ] **Step 7: Commit**

```bash
git add Claudy/Views/Components/TabSwitcher.swift Claudy/Views/FullView.swift Claudy/Views/PortsView.swift Claudy/Theme/Theme.swift Claudy/ViewModels/UsageViewModel.swift Claudy/App/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat: add a usage/ports switch to the card header

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: PortsView et PortRow

**Files:**
- Modify: `Claudy/Views/PortsView.swift` (remplace le fichier provisoire de la Task 7)
- Create: `Claudy/Views/Components/PortRow.swift`

**Interfaces:**
- Consumes: `PortsViewModel`, `ListeningPort`, `PortScanState`, `PortsViewModel.age(since:now:)`
- Produces: `struct PortsView: View`, `struct PortRow: View`

- [ ] **Step 1: Écrire la ligne**

Créer `Claudy/Views/Components/PortRow.swift` :

```swift
import SwiftUI

/// One open port. The kill control stays hidden until the pointer is on the row: an
/// irreversible action has no business being one stray click away at rest.
struct PortRow: View {
    let port: ListeningPort
    let failure: String?
    let onKill: () -> Void

    @State private var isHovered = false
    @State private var isKilling = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(port.port)")
                .font(Theme.Font.value(13, .semibold))
                .foregroundStyle(Theme.Accent.coral.color.opacity(0.95))
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(port.command)
                    .font(Theme.Font.label(11, .medium))
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(subtitle)
                        .font(Theme.Font.label(9.5, .medium))
                        .foregroundStyle(.primary.opacity(0.38))
                        .lineLimit(1)

                    if port.attribution == .orphan {
                        Text("orphelin")
                            .font(Theme.Font.label(8.5, .semibold))
                            .foregroundStyle(Theme.Accent.amber.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.Accent.amber.color.opacity(0.16)))
                    }
                }

                if let failure {
                    Text(failure)
                        .font(Theme.Font.label(9.5, .medium))
                        .foregroundStyle(Theme.danger.opacity(0.9))
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)

            killButton
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var subtitle: String {
        let age = PortsViewModel.age(since: port.startedAt)
        guard let project = port.projectName else { return age }
        return "\(project) · \(age)"
    }

    @ViewBuilder
    private var killButton: some View {
        if isKilling {
            ProgressView()
                .controlSize(.small)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.primary.opacity(0.55))
                .frame(width: 18, height: 18)
                .background(Circle().fill(.primary.opacity(0.08)))
                .opacity(isHovered ? 1 : 0)
                .onTapGesture {
                    isKilling = true
                    onKill()
                }
                .help("Tuer le process du port \(port.port)")
                .accessibilityLabel("Tuer le process du port \(port.port)")
        }
    }
}
```

- [ ] **Step 2: Écrire la vue**

Remplacer entièrement `Claudy/Views/PortsView.swift` :

```swift
import SwiftUI

/// The ports annex: what Claude Code left listening, and a way to close it.
///
/// The empty state is the common case and is written for it — an empty list here is good news,
/// not a failure.
struct PortsView: View {
    @EnvironmentObject private var viewModel: PortsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch viewModel.state {
            case .scanning:
                message("Analyse des ports…")
            case .unavailable(let reason):
                message("Scan indisponible — \(reason)")
            case .ready(let ports) where ports.isEmpty:
                message("Aucun port ouvert par Claude.")
            case .ready(let ports):
                list(ports)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.Motion.accordion, value: viewModel.ports.count)
    }

    private func list(_ ports: [ListeningPort]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ports ouverts par Claude")
                .microLabel(0.55)
                .padding(.bottom, 4)

            ForEach(Array(ports.enumerated()), id: \.element.id) { index, port in
                if index > 0 {
                    Rectangle()
                        .fill(.primary.opacity(0.06))
                        .frame(height: 1)
                }
                PortRow(port: port, failure: viewModel.failures[port.id]) {
                    Task { await viewModel.kill(port) }
                }
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(Theme.Font.label(11, .medium))
            .foregroundStyle(.primary.opacity(0.4))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18)
    }
}
```

- [ ] **Step 3: Compiler**

Run: `xcodebuild build -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Vérifier le comportement réel**

Lancer un serveur depuis une session Claude Code : `python3 -m http.server 4000 --bind 127.0.0.1 &`

Run: `./Scripts/build-app.sh --install`
Expected, dans l'onglet `ports` : une ligne `4000 · Python`, sans pastille orphelin tant que la session Claude vit. Le clic sur la croix la fait disparaître, et `lsof -nP -iTCP:4000 -sTCP:LISTEN` ne retourne plus rien.

Vérifier aussi qu'un serveur lancé hors Claude (`python3 -m http.server 4100` depuis Terminal.app) **n'apparaît pas**.

- [ ] **Step 5: Commit**

```bash
git add Claudy/Views/PortsView.swift Claudy/Views/Components/PortRow.swift
git commit -m "$(cat <<'EOF'
feat: list and kill Claude ports from the card

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Repli quand la lecture d'environnement est refusée

**Files:**
- Modify: `Claudy/Services/PortScanner.swift`
- Modify: `Claudy/Models/PortModels.swift`
- Modify: `Claudy/Views/PortsView.swift`
- Test: `ClaudyTests/PortScannerTests.swift`

**Interfaces:**
- Consumes: `ProcessTable.claudeSessionRoot(of:)`
- Produces:
  - `PortScanState.ready([ListeningPort])` devient `PortScanState.ready([ListeningPort], isDegraded: Bool)`
  - `static func PortScanner.attribute(listeners:table:markers:) -> (ports: [ListeningPort], isDegraded: Bool)`

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `ClaudyTests/PortScannerTests.swift` :

```swift
    /// When the kernel refuses to hand over an environment, attribution falls back to the
    /// process tree: a live session is still recognisable, so the tab keeps working for the
    /// common case instead of showing an empty list.
    func testFallsBackToAncestryWhenEnvironmentIsUnreadable() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 46694, command: "Python", port: 4000, address: "127.0.0.1")],
            table: table([
                RunningProcess(pid: 46694, parent: 8859, startedAt: epoch, arguments: "python3 -m http.server"),
                RunningProcess(pid: 8859, parent: 1, startedAt: epoch, arguments: "/Users/x/.claude/local/claude"),
            ]),
            markers: { _ in nil }
        )
        XCTAssertEqual(result.ports.count, 1)
        XCTAssertEqual(result.ports[0].attribution, .live)
        XCTAssertTrue(result.isDegraded)
    }

    /// The fallback cannot see orphans — that is exactly what the degraded flag warns about.
    func testFallbackDropsOrphans() {
        let result = PortScanner.attribute(
            listeners: [Listener(pid: 95778, command: "bun", port: 37701, address: "127.0.0.1")],
            table: table([RunningProcess(pid: 95778, parent: 1, startedAt: epoch, arguments: "bun worker")]),
            markers: { _ in nil }
        )
        XCTAssertTrue(result.ports.isEmpty)
        XCTAssertTrue(result.isDegraded)
    }
```

Dans le même fichier, adapter les six assertions existantes qui lisent le retour de `attribute` : elles portent désormais sur `result.ports` au lieu du tableau direct (par exemple `XCTAssertEqual(ports.count, 1)` devient `XCTAssertEqual(result.ports.count, 1)`), et `let ports = PortScanner.attribute(...)` devient `let result = PortScanner.attribute(...)`.

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortScannerTests 2>&1 | tail -20`
Expected: FAIL — `value of tuple type has no member 'ports'`.

- [ ] **Step 3: Implémenter le repli**

Dans `Claudy/Models/PortModels.swift`, remplacer le cas `ready` :

```swift
enum PortScanState: Equatable {
    case scanning
    /// `isDegraded` marks a scan that could not read process environments and fell back to
    /// the process tree: live sessions still show, orphans cannot.
    case ready([ListeningPort], isDegraded: Bool)
    case unavailable(String)
}
```

Dans `Claudy/Services/PortScanner.swift`, remplacer `attribute` et l'appel dans `scan()` :

```swift
    static func attribute(
        listeners: [Listener],
        table: ProcessTable,
        markers: (pid_t) -> ProcessEnvironment.Markers?
    ) -> (ports: [ListeningPort], isDegraded: Bool) {
        var isDegraded = false

        let ports = listeners.compactMap { listener -> ListeningPort? in
            guard !isDenied(command: listener.command),
                  let process = table.processes[listener.pid]
            else { return nil }

            let root = table.claudeSessionRoot(of: listener.pid)

            guard let marker = markers(listener.pid) else {
                // No environment: the tree is all that is left to go on.
                isDegraded = true
                guard let root else { return nil }
                return ListeningPort(
                    id: "\(listener.pid)-\(listener.port)",
                    pid: listener.pid, port: listener.port, command: listener.command,
                    projectName: nil, startedAt: process.startedAt,
                    attribution: .live, sessionRootPID: root.pid
                )
            }
            guard marker.isClaude else { return nil }

            return ListeningPort(
                id: "\(listener.pid)-\(listener.port)",
                pid: listener.pid, port: listener.port, command: listener.command,
                projectName: marker.projectDirectory.map { ($0 as NSString).lastPathComponent },
                startedAt: process.startedAt,
                attribution: root == nil ? .orphan : .live,
                sessionRootPID: root?.pid
            )
        }

        return (ports, isDegraded)
    }
```

et dans `scan()` :

```swift
        let result = Self.attribute(
            listeners: Self.parseListeners(output),
            table: table,
            markers: { ProcessEnvironment.markers(pid: $0) }
        )
        return .ready(result.ports.sorted { $0.port < $1.port }, isDegraded: result.isDegraded)
```

Dans `Claudy/ViewModels/PortsViewModel.swift`, adapter l'extraction :

```swift
    var ports: [ListeningPort] {
        if case .ready(let ports, _) = state { return ports }
        return []
    }
```

Dans `Claudy/Views/PortsView.swift`, adapter les deux cas et ajouter l'avertissement :

```swift
            case .ready(let ports, _) where ports.isEmpty:
                message("Aucun port ouvert par Claude.")
            case .ready(let ports, let isDegraded):
                if isDegraded {
                    Text("Environnement des process illisible — les orphelins ne sont pas détectables.")
                        .font(Theme.Font.label(9.5, .medium))
                        .foregroundStyle(Theme.Accent.amber.color.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                list(ports)
```

Adapter enfin les trois assertions de `ClaudyTests/PortsViewModelTests.swift` qui construisent un `.ready(...)` : elles prennent maintenant `isDegraded: false`.

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -20`
Expected: PASS, 10 tests dans `PortScannerTests`, suite complète verte.

- [ ] **Step 5: Commit**

```bash
git add Claudy/Services/PortScanner.swift Claudy/Models/PortModels.swift Claudy/Views/PortsView.swift Claudy/ViewModels/PortsViewModel.swift ClaudyTests
git commit -m "$(cat <<'EOF'
feat: fall back to process ancestry when environments are unreadable

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: « Tout tuer » sur les orphelins

**Files:**
- Modify: `Claudy/ViewModels/PortsViewModel.swift`
- Modify: `Claudy/Views/PortsView.swift`
- Test: `ClaudyTests/PortsViewModelTests.swift`

**Interfaces:**
- Consumes: `PortsViewModel.kill(_:)`, `PortsViewModel.orphanCount`
- Produces:
  - `var PortsViewModel.orphans: [ListeningPort]`
  - `func PortsViewModel.killAllOrphans() async`
  - `@Published var PortsViewModel.isConfirmingBulkKill: Bool`

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter à `ClaudyTests/PortsViewModelTests.swift` :

```swift
    /// The bulk action never touches a live session's ports — only what Claude left behind.
    func testBulkTargetsOrphansOnly() async {
        let model = PortsViewModel(
            scanner: StubScanner(result: .ready([port(500, .orphan), port(501, .live), port(502, .orphan)],
                                                isDegraded: false))
        )
        await model.refresh()
        XCTAssertEqual(model.orphans.map(\.pid), [500, 502])
    }

    func testBulkConfirmationIsRequiredBeforeAnyKill() async {
        let model = PortsViewModel(
            scanner: StubScanner(result: .ready([port(500, .orphan)], isDegraded: false))
        )
        await model.refresh()
        XCTAssertFalse(model.isConfirmingBulkKill)
        model.requestBulkKill()
        XCTAssertTrue(model.isConfirmingBulkKill)
    }
```

- [ ] **Step 2: Lancer les tests pour vérifier l'échec**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortsViewModelTests 2>&1 | tail -20`
Expected: FAIL — `value of type 'PortsViewModel' has no member 'orphans'`.

- [ ] **Step 3: Implémenter**

Dans `Claudy/ViewModels/PortsViewModel.swift`, ajouter :

```swift
    /// Raised while the confirmation is on screen. A bulk kill is the one action here that can
    /// take several processes down at once, so it never fires straight off a click.
    @Published var isConfirmingBulkKill = false

    var orphans: [ListeningPort] {
        ports.filter { $0.attribution == .orphan }
    }

    func requestBulkKill() {
        guard !orphans.isEmpty else { return }
        isConfirmingBulkKill = true
    }

    func killAllOrphans() async {
        isConfirmingBulkKill = false
        for port in orphans {
            await kill(port)
        }
    }
```

et remplacer `orphanCount` par `var orphanCount: Int { orphans.count }`.

Dans `Claudy/Views/PortsView.swift`, ajouter le pied de liste dans `list(_:)`, après la boucle `ForEach` :

```swift
            if viewModel.orphanCount > 1 {
                Button {
                    viewModel.requestBulkKill()
                } label: {
                    Text("Tuer les \(viewModel.orphanCount) orphelins")
                        .font(Theme.Font.label(9.5, .semibold))
                        .foregroundStyle(Theme.danger.opacity(0.9))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
```

et attacher la confirmation au `VStack` racine de `body` :

```swift
        .confirmationDialog(
            "Tuer \(viewModel.orphanCount) process ?",
            isPresented: $viewModel.isConfirmingBulkKill,
            titleVisibility: .visible
        ) {
            Button("Tuer \(viewModel.orphans.map { String($0.port) }.joined(separator: ", "))", role: .destructive) {
                Task { await viewModel.killAllOrphans() }
            }
            Button("Annuler", role: .cancel) {}
        }
```

- [ ] **Step 4: Lancer les tests pour vérifier le succès**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' -only-testing:ClaudyTests/PortsViewModelTests 2>&1 | tail -20`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add Claudy/ViewModels/PortsViewModel.swift Claudy/Views/PortsView.swift ClaudyTests/PortsViewModelTests.swift
git commit -m "$(cat <<'EOF'
feat: kill every orphaned Claude port behind one confirmation

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Documentation et suite de tests complète

**Files:**
- Modify: `README.md`
- Modify: `README.fr.md`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: tout ce qui précède
- Produces: rien de code

- [ ] **Step 1: Lancer la suite complète**

Run: `xcodebuild test -project Claudy.xcodeproj -scheme Claudy -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `TEST SUCCEEDED`, 38 tests (1 + 6 + 7 + 10 + 8 + 6).

- [ ] **Step 2: Documenter la fonctionnalité et sa portée**

Dans `README.md`, après le paragraphe « Your data stays with you », ajouter :

```markdown
## Ports

A second tab lists the TCP ports Claude Code left listening — including the ones whose
session has already exited — and closes them on a click. Attribution reads the Claude
markers a process inherits in its environment, so nothing else on your machine is ever
listed, and nothing is killed without your click. The environment itself is never read
beyond those markers, never stored and never logged.
```

Dans `README.fr.md`, au même endroit :

```markdown
## Ports

Un second onglet liste les ports TCP laissés en écoute par Claude Code — y compris ceux
dont la session est déjà terminée — et les ferme d'un clic. L'attribution lit les marqueurs
Claude hérités dans l'environnement du process : rien d'autre sur la machine n'est listé, et
rien n'est tué sans ton clic. L'environnement lui-même n'est jamais lu au-delà de ces
marqueurs, jamais stocké, jamais journalisé.
```

Dans `CHANGELOG.md`, ajouter une entrée en tête, sous la forme déjà utilisée par le fichier :

```markdown
- Onglet Ports : liste les ports laissés en écoute par Claude Code, orphelins compris, et permet de les tuer un par un.
```

- [ ] **Step 3: Commit**

```bash
git add README.md README.fr.md CHANGELOG.md
git commit -m "$(cat <<'EOF'
docs: document the ports tab and its attribution rule

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
EOF
)"
```
