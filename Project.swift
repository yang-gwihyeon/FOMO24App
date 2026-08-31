import ProjectDescription

// 공통 빌드 설정
let teamID = "33YSUT6XZ3"
// 릴리즈 CI가 태그에서 버전을 주입: v1.1 푸시 → TUIST_MARKETING_VERSION=1.1,
// TUIST_BUILD_NUMBER=<GitHub run number>. 로컬 빌드는 아래 기본값 사용.
let marketingVersion = Environment.marketingVersion.getString(default: "1.1")
let buildNumber = Environment.buildNumber.getString(default: "5")
let baseSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": .string(teamID),
    "CODE_SIGN_STYLE": "Automatic",
    "MARKETING_VERSION": .string(marketingVersion),
    "CURRENT_PROJECT_VERSION": .string(buildNumber),
    "TARGETED_DEVICE_FAMILY": "1,2",
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
]

let project = Project(
    name: "FOMO24",
    options: .options(automaticSchemesOptions: .disabled),
    packages: [
        .remote(url: "https://github.com/firebase/firebase-ios-sdk.git",
                requirement: .upToNextMajor(from: "11.0.0")),
        .remote(url: "https://github.com/phosphor-icons/swift",
                requirement: .upToNextMajor(from: "2.0.0")),
    ],
    settings: .settings(base: baseSettings),
    targets: [
        // MARK: 모듈 — 순수 모델/도메인 (외부 의존성 없음)
        .target(
            name: "FOMOCore",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.yang.FOMO24.FOMOCore",
            deploymentTargets: .iOS("17.0"),
            sources: ["Modules/FOMOCore/Sources/**"]
        ),
        // MARK: 모듈 — 거래소 시세 서비스
        .target(
            name: "MarketKit",
            destinations: .iOS,
            product: .staticFramework,
            bundleId: "com.yang.FOMO24.MarketKit",
            deploymentTargets: .iOS("17.0"),
            sources: ["Modules/MarketKit/Sources/**"],
            dependencies: [.target(name: "FOMOCore")]
        ),
        // MARK: 앱
        .target(
            name: "FOMO24",
            destinations: .iOS,
            product: .app,
            bundleId: "com.yang.FOMO24",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "Info.plist"),
            sources: ["Sources/**"],
            resources: ["Resources/**", "GoogleService-Info.plist"],
            entitlements: "FOMO24.entitlements",
            dependencies: [
                .target(name: "FOMOCore"),
                .target(name: "MarketKit"),
                .target(name: "FOMO24Widgets"),
                .package(product: "FirebaseMessaging"),
                .package(product: "FirebaseFirestore"),
                .package(product: "PhosphorSwift"),
            ],
            settings: .settings(base: ["ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"])
        ),
        // MARK: 위젯 익스텐션
        .target(
            name: "FOMO24Widgets",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "com.yang.FOMO24.Widgets",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .file(path: "Widgets/Info.plist"),
            sources: ["Widgets/**"],
            dependencies: [.target(name: "FOMOCore")],
            settings: .settings(base: ["SKIP_INSTALL": "YES"])
        ),
        // MARK: 테스트
        .target(
            name: "FOMOCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.yang.FOMO24.FOMOCoreTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Modules/FOMOCore/Tests/**"],
            dependencies: [.target(name: "FOMOCore")]
        ),
        .target(
            name: "MarketKitTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "com.yang.FOMO24.MarketKitTests",
            deploymentTargets: .iOS("17.0"),
            sources: ["Modules/MarketKit/Tests/**"],
            dependencies: [.target(name: "MarketKit")]
        ),
    ],
    schemes: [
        .scheme(
            name: "FOMO24",
            shared: true,
            buildAction: .buildAction(targets: ["FOMO24"]),
            testAction: .targets(["FOMOCoreTests", "MarketKitTests"]),
            runAction: .runAction(executable: "FOMO24")
        ),
        .scheme(
            name: "FOMO24Widgets",
            shared: true,
            buildAction: .buildAction(targets: ["FOMO24Widgets"]),
            runAction: .runAction(executable: "FOMO24")
        ),
        .scheme(
            name: "Modules",
            shared: true,
            buildAction: .buildAction(targets: ["FOMOCore", "MarketKit"]),
            testAction: .targets(["FOMOCoreTests", "MarketKitTests"])
        ),
    ]
)
