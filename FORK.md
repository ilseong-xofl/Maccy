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
- 이미지 크기는 기존 `이미지 세로 높이` 설정으로 조절합니다. 텍스트 줄 수와는 별도입니다.
- 별도 미리보기 패널은 기본적으로 자동으로 열리지 않습니다. 필요하면 `⌃Space`로 열거나 모양 설정에서 자동 열기를 켤 수 있습니다.
- 코드 구문 색상 및 원문 서식 재현은 이 버전에 포함하지 않습니다.

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

## 라이선스

원본 Maccy의 MIT 라이선스와 저작권 고지를 유지합니다. [LICENSE](LICENSE)를 참조하세요.
