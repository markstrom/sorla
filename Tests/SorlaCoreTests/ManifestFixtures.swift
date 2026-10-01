enum ManifestFixtures {
    // Published manifest for version 1.0.0, verbatim.
    static let published = #"""
{
  "schema": 1,
  "models": [
    {
      "id": "pianissimo-sv",
      "name": "Pianissimo (Swedish)",
      "version": "1.0.0",
      "source": {
        "repo": "KlangAI/pianissimo-sv",
        "revision": "8f1f6d8f8bd7482a5ea1d2bfaf6ef5be61597138"
      },
      "license": "CC-BY-4.0",
      "credit": "Klang Pianissimo by Klang AI AB",
      "loader": {
        "library": "FluidAudio",
        "version": "v3"
      },
      "totalSize": 688257471,
      "files": [
        {
          "path": "Decoder.mlpackage/Data/com.apple.CoreML/model.mlmodel",
          "size": 11811,
          "sha256": "4a36039f091573251bd8bcb55e8f5fa6dc3bad32052d825b1e3b2a3840879990"
        },
        {
          "path": "Decoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
          "size": 23604992,
          "sha256": "9e34a5cc5da3477cf0e49126f55d4754a6a332b5df52a22812d6ddbd84af0e39"
        },
        {
          "path": "Decoder.mlpackage/Manifest.json",
          "size": 617,
          "sha256": "99e8049015d297e58291cfe279c832f01e88959ca91894be939753b19f694827"
        },
        {
          "path": "Encoder.mlpackage/Data/com.apple.CoreML/model.mlmodel",
          "size": 677050,
          "sha256": "9c9e8a95b18b35142f00ac3c8c186c669057f7ca4a097b2e463c99486eb8eeb8"
        },
        {
          "path": "Encoder.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
          "size": 649181632,
          "sha256": "e9623b969e8f31ba12bfbec7cdcdacb3bfb74e5a3a9bd3a812e4a942c1b1b9ed"
        },
        {
          "path": "Encoder.mlpackage/Manifest.json",
          "size": 617,
          "sha256": "6d235c39782d2e839142f0df9a6fc3096a6258da05f8be1c1d95547d936cf619"
        },
        {
          "path": "JointDecisionv3.mlpackage/Data/com.apple.CoreML/model.mlmodel",
          "size": 10827,
          "sha256": "af1b876c8677cc8c6676573801038ce6da4972eba4817b1caa2eb09b9ff5ed32"
        },
        {
          "path": "JointDecisionv3.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
          "size": 12642764,
          "sha256": "1f841daf3a6ce483ac136cd7a5e48d6071543e7c5eddcbba4525bda74695cb61"
        },
        {
          "path": "JointDecisionv3.mlpackage/Manifest.json",
          "size": 617,
          "sha256": "42ab119e793f459e4a8d4a86f77714f093a54ebea55a14786981962985e8121d"
        },
        {
          "path": "LICENSE-and-attribution.txt",
          "size": 2402,
          "sha256": "cebcc87c23d9b4df78a1e1655b20c5f82e66babde45362a58fe6a2cb64f3dc91"
        },
        {
          "path": "Preprocessor.mlpackage/Data/com.apple.CoreML/model.mlmodel",
          "size": 17913,
          "sha256": "44426745838b32d86e0de13054eea2b7c4439e95dadef0bcfa528bdfc93eb630"
        },
        {
          "path": "Preprocessor.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
          "size": 1953088,
          "sha256": "c69139820fc62c199f92c83d2c97458f8aaff337e5026abd9606ff03ba52b8e1"
        },
        {
          "path": "Preprocessor.mlpackage/Manifest.json",
          "size": 617,
          "sha256": "caffd54a12af3df9bb673f100239919e1047ece8c4035f75819f4adc1d71b6a9"
        },
        {
          "path": "README.md",
          "size": 1402,
          "sha256": "348778dc766508a6a1ae97b8a0a080b5874c37756ecacb0562fd62192e75ff3a"
        },
        {
          "path": "parakeet_vocab.json",
          "size": 151122,
          "sha256": "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"
        }
      ]
    }
  ]
}
"""#

    // Published manifest for the precompiled 1.1.0 (tag 1.1.0-compiled), verbatim including its final newline.
    static let compiled = #"""
{
  "schema": 1,
  "models": [
    {
      "id": "pianissimo-sv",
      "name": "Pianissimo (Swedish)",
      "version": "1.1.0",
      "source": {
        "repo": "KlangAI/pianissimo-sv",
        "revision": "8f1f6d8f8bd7482a5ea1d2bfaf6ef5be61597138"
      },
      "license": "CC-BY-4.0",
      "credit": "Klang Pianissimo by Klang AI AB",
      "loader": {
        "library": "FluidAudio",
        "version": "v3"
      },
      "format": "mlmodelc",
      "minimumOS": {
        "iOS": "26.0",
        "macOS": "26.0"
      },
      "compiledFrom": {
        "revision": "106fa163a138a0db6737e0c50494269e07f508d0",
        "compiler": "coremlcompiler 3600.25.1 (Xcode 27.0), deployment target 26.0"
      },
      "totalSize": 688595324,
      "files": [
        {
          "path": "Decoder.mlmodelc/analytics/coremldata.bin",
          "size": 243,
          "sha256": "f172c15a50f309f5bd296bdde67465c751e04d3341f578870ae415c334ac04d2"
        },
        {
          "path": "Decoder.mlmodelc/coremldata.bin",
          "size": 693,
          "sha256": "2192e1baeac694eddedd142a2cfa43f421e60961c6c58fcd2ee32defc7926e49"
        },
        {
          "path": "Decoder.mlmodelc/metadata.json",
          "size": 3599,
          "sha256": "8046a45e005ec3226c16d7aea63f6d0040f4fc3a26da6e65233d7e41358d6e1d"
        },
        {
          "path": "Decoder.mlmodelc/model.mil",
          "size": 13110,
          "sha256": "34bd2cc0a00dd7a485f0aa90f58d6b516c94ee8f4842de92aad7b581849df289"
        },
        {
          "path": "Decoder.mlmodelc/weights/weight.bin",
          "size": 23604992,
          "sha256": "9e34a5cc5da3477cf0e49126f55d4754a6a332b5df52a22812d6ddbd84af0e39"
        },
        {
          "path": "Encoder.mlmodelc/analytics/coremldata.bin",
          "size": 243,
          "sha256": "d2f394285367a7a1db5d563072cd06b998a493e9fd1d3b2ee85cfbb45cd35855"
        },
        {
          "path": "Encoder.mlmodelc/coremldata.bin",
          "size": 681,
          "sha256": "4b815f51d37de350d752ff32ea619352038dc8f3d931d885c14d84199beeb4c1"
        },
        {
          "path": "Encoder.mlmodelc/metadata.json",
          "size": 3146,
          "sha256": "ac2ed8dc3f5abec3fdc4a0ff166264cf6dcaa862377d005a8e3c2f5c0a3836c0"
        },
        {
          "path": "Encoder.mlmodelc/model.mil",
          "size": 991866,
          "sha256": "23b136db7ed05efb2c1888330e1610b3038177144f4b118de7694ef9e85eeaed"
        },
        {
          "path": "Encoder.mlmodelc/weights/weight.bin",
          "size": 649181632,
          "sha256": "e9623b969e8f31ba12bfbec7cdcdacb3bfb74e5a3a9bd3a812e4a942c1b1b9ed"
        },
        {
          "path": "JointDecisionv3.mlmodelc/analytics/coremldata.bin",
          "size": 243,
          "sha256": "a3d3094441bfc2b7006dd25144269ea59ff1d54403b7801f24a4d3028c6ec617"
        },
        {
          "path": "JointDecisionv3.mlmodelc/coremldata.bin",
          "size": 740,
          "sha256": "74843f3c1b075b1fbb017b04e21f05a9cfb3578ca474eb605877fdefc73dd02c"
        },
        {
          "path": "JointDecisionv3.mlmodelc/metadata.json",
          "size": 3758,
          "sha256": "e932f2aaed90f9ebf67905009280f8963f4c1a5297fcc51d7b5af3966ed311cd"
        },
        {
          "path": "JointDecisionv3.mlmodelc/model.mil",
          "size": 11777,
          "sha256": "167357ff6d558349e745047c6e3f610010d047ec21ab6f56df2dbb041f096baa"
        },
        {
          "path": "JointDecisionv3.mlmodelc/weights/weight.bin",
          "size": 12642764,
          "sha256": "1f841daf3a6ce483ac136cd7a5e48d6071543e7c5eddcbba4525bda74695cb61"
        },
        {
          "path": "LICENSE-and-attribution.txt",
          "size": 2907,
          "sha256": "c31f5df3b9f4b683c3ebcf180dcc5ff2c41acfb42e1e1fd66b58fc55b10d144c"
        },
        {
          "path": "Preprocessor.mlmodelc/analytics/coremldata.bin",
          "size": 243,
          "sha256": "791541080e887157342fb733e8d5c56ef5bf317ce62f3f21650c7157e7f38256"
        },
        {
          "path": "Preprocessor.mlmodelc/coremldata.bin",
          "size": 633,
          "sha256": "8f314d8ab7016a8e1d2c3649b43fbacaa75e984adf89306a23c2628fbfee5d6a"
        },
        {
          "path": "Preprocessor.mlmodelc/metadata.json",
          "size": 2992,
          "sha256": "f42f7326bb74f52bf215721f4bfc8ca1bd682c60f31f83662b5f7577d8d32dd7"
        },
        {
          "path": "Preprocessor.mlmodelc/model.mil",
          "size": 24852,
          "sha256": "3533d2b668a4ec0df487eec1cf9a06372817254538c9738536dcf60e656ef1d6"
        },
        {
          "path": "Preprocessor.mlmodelc/weights/weight.bin",
          "size": 1953088,
          "sha256": "c69139820fc62c199f92c83d2c97458f8aaff337e5026abd9606ff03ba52b8e1"
        },
        {
          "path": "parakeet_vocab.json",
          "size": 151122,
          "sha256": "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"
        }
      ]
    }
  ]
}

"""#
}
