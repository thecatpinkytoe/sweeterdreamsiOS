HealthExportKit - Cloud Build (Codemagic) package
Generated: 2025-11-27T22:37:16.263925Z

This archive contains a minimal SwiftUI app source and build configuration designed for cloud-based builds (e.g., Codemagic).
It uses xcodegen to create an Xcode project on the CI machine, so you do NOT need Xcode locally.

How to use (high level):
1) Upload this repository to your Git provider (GitHub/GitLab/Bitbucket).
2) Create a Codemagic project and connect your repo.
3) Configure code signing in Codemagic (App Store Connect API key or provisioning profiles).
4) Run the 'build-and-export' workflow. Codemagic will install xcodegen, generate the Xcode project, build and export an IPA.
5) Download the IPA and install on device via AltStore / Apple Configurator / TestFlight (if signed and distributed).

Files included:
- project.yml            -> xcodegen project description
- codemagic.yaml         -> Codemagic workflow to generate & build project
- exportOptions.plist    -> placeholder export options (edit on CI for your signing)
- Sources/HealthExportKit/*.swift -> Swift source files
- Resources/Info.plist   -> minimal Info.plist (edit bundle id & privacy strings)
- Resources/exportImage.png -> placeholder icon (not required)

NOTE: You will need to configure code signing on the CI (Codemagic supports App Store Connect API key or provisioning profiles).
If you want, I can produce a second ZIP that includes fastlane match or more advanced signing steps.
