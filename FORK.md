# Maccy Preview

[Maccy](https://github.com/p0deje/Maccy)의 UI를 수정한 독립 개발 버전입니다. 원본 기준 커밋: `a92c11ae3e7a86a57dc6359bad59e330e4625ede`.

## 사용법

1. `Maccy Preview.app`을 실행합니다. 메뉴 막대 아이콘이나 기본 단축키 `⇧⌘C`로 목록을 엽니다.
2. 창 가장자리 또는 모서리를 드래그해 가로·세로 크기를 조절합니다. 마지막 크기를 기억합니다.
3. `설정… → 모양 → 텍스트 최대 표시 줄 수`에서 1–20줄을 설정합니다. 기본값은 5줄입니다.
4. 짧은 항목은 필요한 높이만 사용하고, 긴 항목은 자동 줄바꿈한 표시 줄 수를 기준으로 제한합니다. 고정한 항목도 목록과 함께 스크롤됩니다.
5. 검색, 키보드 선택, 복사·붙여넣기는 기존 Maccy 방식으로 사용합니다. 자동 붙여넣기를 사용하려면 macOS 손쉬운 사용 권한에 이 앱을 별도로 추가해야 합니다.

기존 Maccy와 기본 단축키가 같습니다. 동시에 실행한다면 한쪽의 열기 단축키를 설정에서 변경하세요.

## 표시 규칙

- 원래 개행과 들여쓰기를 보존하며, 가로 폭에 따라 다시 줄바꿈합니다.
- 표시 제한은 미리보기에만 적용합니다. 실제 클립보드 데이터는 자르지 않습니다.
- 직접 지정한 별칭은 기존처럼 목록 내용을 대신합니다.
- 검색과 검색 강조는 같은 목록 텍스트를 사용합니다.
- 긴 텍스트는 성능을 위해 목록에서 전체 10,000자까지 준비하며, 기존 미리보기의 단락당 10,000바이트 제한도 적용됩니다. 잘린 내용에는 생략 표시가 붙습니다. 퍼지 검색은 기존의 약 5,000자 범위를 유지합니다.
- 별도 미리보기 패널은 기본적으로 자동으로 열리지 않습니다. 필요하면 `⌃Space`로 열거나 모양 설정에서 자동 열기를 켤 수 있습니다.
- 코드 구문 색상 및 원문 서식 재현은 이 버전에 포함하지 않습니다.

## 이미지 표시

- `설정… → 모양 → 최대 이미지 높이`에서 1–600을 설정합니다. 기본값은 300이며 텍스트 줄 수와 별도입니다. 기존에 저장한 값은 유지합니다. 업데이트 후 이미지가 작게 보이면 이 설정에 작은 값이 남아 있는지 확인하고 원하는 높이로 변경하세요.
- 창 너비와 최대 높이 안에 이미지 전체가 들어오도록 비율을 유지하며, 항목 안에서 가로 중앙에 표시합니다. 행 높이는 실제 표시 크기에 맞추며, 작은 이미지는 확대하지 않습니다.
- 클립보드의 PNG·TIFF·JPEG·HEIC 이미지 데이터를 먼저 사용합니다. 표시 가능한 이미지 데이터가 없으면 단일 `fileURL`이 가리키는 로컬 이미지 파일을 읽어 표시합니다.
- 미리보기만 생성하므로 저장한 클립보드 내용과 붙여넣기 형식은 유지합니다. 복사한 파일이 썸네일 이미지로 바뀌지 않습니다.
- Finder에서 단일 이미지 파일을 복사할 때 해당 파일의 읽기 권한을 앱 기록에 별도로 저장합니다. 이전에 저장한 항목에 읽기 권한이 없어 경로만 보이면 Finder에서 해당 파일을 한 번 다시 복사하세요.
- 원격 URL, 일반 텍스트로 복사한 경로, 여러 파일 목록은 이미지로 바꾸지 않습니다. 파일이 없거나 읽기 권한이 없거나 손상되었다면 경로 등 기존 텍스트를 표시합니다.

미리보기는 ImageIO로 비동기 생성하며, 방향 정보를 적용하고 긴 변을 최대 2,048픽셀로 축소합니다. 원본 파일과 클립보드 바이트는 수정하지 않습니다.

파일 접근 정보는 원본 클립보드 내용과 분리된 읽기 전용 보안 북마크로 보관합니다. 재복사한 동일 항목에 새 북마크가 없으면 기존 것을 유지합니다. 읽을 때는 별도 승인 창이나 볼륨 마운트 없이 북마크를 해석하며, 접근할 수 없는 파일은 텍스트로 표시합니다.

## 독립 실행과 빌드

- 앱 이름: `Maccy Preview`
- Bundle ID: `io.github.ilseong-xofl.MaccyPreview`
- 저장 경로: 앱의 Application Support 안 `Maccy Preview/Storage.sqlite`
- macOS 14 이상, Swift/Xcode 프로젝트입니다. 이 작업에서는 Xcode 27로 빌드했습니다.
- 로컬 ad-hoc 서명을 사용합니다. Apple Developer ID 서명·공증 및 배포용 자동 업데이트는 구성하지 않았습니다.
- 원본 업데이트 엔진인 Sparkle 의존성도 제거했습니다. 이 앱은 원본 Maccy 업데이트를 내려받거나 설치하지 않습니다.
- 원본 Maccy의 기록을 자동으로 가져오지 않습니다.

```sh
xcodebuild build -project Maccy.xcodeproj -scheme Maccy \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build
open 'build/Build/Products/Release/Maccy Preview.app'
```

테스트:

```sh
xcodebuild test -project Maccy.xcodeproj -scheme Maccy \
  -configuration Debug -destination 'platform=macOS' \
  -only-testing:MaccyTests/HistoryItemDecoratorTests \
  -only-testing:MaccyTests/ClipboardImagePreviewTests \
  -only-testing:MaccyTests/ImageRowLayoutTests \
  -only-testing:MaccyTests/FloatingPanelSizingTests \
  -only-testing:MaccyTests/SearchTests \
  -only-testing:MaccyTests/HistoryItemTests \
  -only-testing:MaccyTests/UnsafeForTitleLayoutTests \
  -only-testing:MaccyTests/ShortenedTests
```

Debug 빌드에만 `preview-demo` 인수가 있습니다. 메모리 DB에 합성 샘플을 넣고 클립보드 감시를 끈 상태로 창을 표시합니다. 일반 사용자 기록과 분리된 테스트 설정을 사용합니다. 데모 설정은 실행할 때 초기화됩니다.

```sh
open 'build/Build/Products/Debug/Maccy Preview.app' --args preview-demo
```

이미지 파일을 테스트 항목으로 추가하려면 절대 경로를 전달합니다. 파일 URL만 담은 항목을 메모리 DB에 추가하며 시스템 클립보드는 변경하지 않습니다.

```sh
open 'build/Build/Products/Debug/Maccy Preview.app' --args preview-demo \
  --preview-image '/absolute/file.png'
```

## 라이선스

원본 Maccy의 MIT 라이선스와 저작권 고지를 유지합니다. [LICENSE](LICENSE)를 참조하세요.
