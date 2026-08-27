import ReplayKit
import UIKit

final class SetupViewController: UIViewController {
    private let serverField = UITextField()
    private let keyField = UITextField()
    private let messageLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        configureInterface()
    }

    private func configureInterface() {
        view.backgroundColor = .systemBackground
        preferredContentSize = CGSize(width: 520, height: 430)

        let titleLabel = UILabel()
        titleLabel.text = "Transmitir pantalla con StudioPad"
        titleLabel.font = .preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true

        let descriptionLabel = UILabel()
        descriptionLabel.text = "Pega la dirección RTMP/RTMPS y la clave de YouTube, Twitch, Kick u otro servicio."
        descriptionLabel.font = .preferredFont(forTextStyle: .body)
        descriptionLabel.textColor = .secondaryLabel
        descriptionLabel.numberOfLines = 0

        serverField.placeholder = "rtmps://servidor/app"
        serverField.borderStyle = .roundedRect
        serverField.keyboardType = .URL
        serverField.autocapitalizationType = .none
        serverField.autocorrectionType = .no
        serverField.textContentType = .URL
        serverField.accessibilityLabel = "URL del servidor"

        keyField.placeholder = "Clave de transmisión"
        keyField.borderStyle = .roundedRect
        keyField.autocapitalizationType = .none
        keyField.autocorrectionType = .no
        keyField.isSecureTextEntry = true
        keyField.accessibilityLabel = "Clave de transmisión"

        messageLabel.font = .preferredFont(forTextStyle: .footnote)
        messageLabel.textColor = .systemRed
        messageLabel.numberOfLines = 0
        messageLabel.isHidden = true

        let startButton = UIButton(type: .system)
        var startConfiguration = UIButton.Configuration.filled()
        startConfiguration.title = "Continuar"
        startConfiguration.cornerStyle = .large
        startButton.configuration = startConfiguration
        startButton.addTarget(self, action: #selector(startBroadcast), for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancelar", for: .normal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)

        let buttons = UIStackView(arrangedSubviews: [cancelButton, startButton])
        buttons.axis = .horizontal
        buttons.spacing = 16
        buttons.distribution = .fillEqually

        let stack = UIStackView(arrangedSubviews: [
            titleLabel,
            descriptionLabel,
            serverField,
            keyField,
            messageLabel,
            buttons
        ])
        stack.axis = .vertical
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            serverField.heightAnchor.constraint(equalToConstant: 48),
            keyField.heightAnchor.constraint(equalToConstant: 48),
            startButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    @objc private func startBroadcast() {
        let server = (serverField.text ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let key = (keyField.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard (server.hasPrefix("rtmp://") || server.hasPrefix("rtmps://")), !key.isEmpty else {
            messageLabel.text = "Comprueba la dirección del servidor y la clave."
            messageLabel.isHidden = false
            return
        }

        let fullURL = server + "/" + key
        guard URL(string: fullURL) != nil else {
            messageLabel.text = "La dirección completa no es válida."
            messageLabel.isHidden = false
            return
        }

        extensionContext?.completeRequest(
            withBroadcast: BroadcastConstants.displayURL,
            setupInfo: [
                BroadcastConstants.streamURLKey: fullURL as NSString,
                BroadcastConstants.videoBitRateKey: 4_000_000 as NSNumber,
                BroadcastConstants.framesPerSecondKey: 30 as NSNumber
            ]
        )
    }

    @objc private func cancel() {
        let error = NSError(
            domain: "StudioPad.BroadcastSetup",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Configuración cancelada"]
        )
        extensionContext?.cancelRequest(withError: error)
    }
}
