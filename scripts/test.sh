#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p .build
swiftc -parse-as-library Sources/DeskGPT/ModelRouter.swift Sources/DeskGPT/CreationModels.swift Sources/DeskGPT/ImageClient.swift Sources/DeskGPT/CreationStore.swift Sources/DeskGPT/Models.swift Sources/DeskGPT/Services.swift Sources/DeskGPT/CompatibleClient.swift Sources/DeskGPT/Store.swift Tests/DeskGPTTests/CoreTests.swift -o .build/core-tests
.build/core-tests
