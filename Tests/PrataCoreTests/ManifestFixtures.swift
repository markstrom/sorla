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
}
