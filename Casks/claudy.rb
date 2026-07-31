# Cask Homebrew de Claudy.
#
# Publication : copier ce fichier dans le tap `Endikk/homebrew-claudy` (répertoire Casks/),
# puis mettre à jour `version` et `sha256` à chaque release :
#   shasum -a 256 dist/Claudy-<version>.zip
#
# Installation utilisateur :
#   brew install --cask Endikk/claudy/claudy
cask "claudy" do
  version "1.1.0"
  sha256 :no_check # remplacer par le SHA-256 du zip de la release correspondante

  url "https://github.com/Endikk/Claudy/releases/download/v#{version}/Claudy-#{version}.zip"
  name "Claudy"
  desc "Widget de bureau affichant les quotas et la consommation Claude en temps réel"
  homepage "https://github.com/Endikk/Claudy"

  depends_on macos: ">= :ventura"

  app "Claudy.app"

  # L'app n'est pas notarisée (distribution gratuite, sans compte Apple Developer) :
  # sans ce retrait de quarantaine, Gatekeeper refuserait de la lancer.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Claudy.app"],
                   sudo: false
  end

  uninstall quit: "com.claudy.Claudy"

  zap trash: [
    "~/Library/Application Support/Claudy",
    "~/Library/Preferences/com.claudy.Claudy.plist",
  ]

  caveats <<~EOS
    Claudy n'est pas notarisé par Apple (projet gratuit, sans compte développeur payant).
    Le cask retire la quarantaine automatiquement. Le code est open source :
    https://github.com/Endikk/Claudy — compile-le toi-même si tu préfères.
  EOS
end
