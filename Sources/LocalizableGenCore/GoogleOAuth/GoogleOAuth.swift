//
//  GoogleOAuth.swift
//  LocalizableGenerator
//
//  Created by Huy Nguyen on 29/03/2022.
//

import Foundation
import OAuth2

struct GoogleOAuthError<Reason>: Error {
    var reason: Reason

    init(reason: Reason) {
        self.reason = reason
    }
}

extension GoogleOAuthError: CustomStringConvertible {
    var description: String {
        return """
        GoogleOAuth encountered an error with reason: \(reason)
        """
    }
}

enum CredentialsErrorReason {
    case processInfoNotDefined
    case parseCredentialsData
    case jsonDecoder
}

enum TokenProviderErrorReason {
    case defaultTokenProvider
    case withTokenError(Error?)
    case accessTokenEmpty
    case failedToAsTokenProviderError
    case unknown
}

typealias CredentialsError = GoogleOAuthError<CredentialsErrorReason>
typealias TokenProviderError = GoogleOAuthError<TokenProviderErrorReason>

extension Error {
    func asTo<T>(_ error: T.Type) -> T {
        return self as! T
    }
}

class GoogleOAuth {

    static let share = GoogleOAuth()

    public private(set) var accessToken: String = ""

    init() {
        try? buildCredentialsJSONFile()
    }

    func buildCredentialsJSONFile() throws {
        do {
            guard let credentialsPath = ProcessInfo.processInfo.environment[Constant.App.credentialKey] else {
                throw CredentialsError(reason: .processInfoNotDefined)
            }
            let credentialsURL = URL(fileURLWithPath: credentialsPath)
            let fileName = credentialsURL.lastPathComponent
            let folderBuild = credentialsURL.deletingLastPathComponent()
            let folder = try Folder(path: folderBuild.path + "/")
            let file = try folder.createFile(named: fileName)
            let credentials = Constant.OAuth.Credentials.self
            let serviceAccount = ServiceAccountCredentials(
                CredentialType: credentials.type,
                ProjectId: credentials.projectId,
                PrivateKeyId: credentials.privateKeyId,
                PrivateKey: credentials.privateKey,
                ClientEmail: credentials.clientEmail,
                ClientID: credentials.clientID,
                AuthURI: credentials.authURI,
                TokenURI: credentials.tokenURI,
                AuthProviderX509CertURL: credentials.authProviderX509CertURL,
                ClientX509CertURL: credentials.clientX509CertURL
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(serviceAccount)
            try file.write(data)
        } catch {
            WriteError(path: error.asTo(WriteError.self).path, reason: .fileCreationFailed)
        }
    }

    func getCredentialEmail() throws -> String {
        guard let credentialsPath = ProcessInfo.processInfo.environment[Constant.App.credentialKey] else {
            throw CredentialsError(reason: .processInfoNotDefined)
        }

        guard let credentialsData = try? Data(contentsOf: URL(fileURLWithPath: credentialsPath), options:[]) else {
            throw CredentialsError(reason: .parseCredentialsData)
        }

        guard let credentials = try? JSONDecoder().decode(ServiceAccountCredentials.self, from: credentialsData) else {
            throw CredentialsError(reason: .jsonDecoder)
        }

        return credentials.ClientEmail
    }

    func connect() throws {
        guard let provider = DefaultTokenProvider(scopes: Constant.OAuth.scopes) else {
            throw TokenProviderError(reason: .defaultTokenProvider)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var tokenProviderError: TokenProviderError = .init(reason: .unknown)
        try provider.withToken({ token, error in
            guard error == nil else {
                tokenProviderError = TokenProviderError(reason: .withTokenError(error))
                return
            }
            guard let accessToken = token?.AccessToken else {
                tokenProviderError = TokenProviderError(reason: .accessTokenEmpty)
                return
            }
            self.accessToken = accessToken
            semaphore.signal()
        })
        semaphore.wait()
        guard !accessToken.isEmpty else {
            throw tokenProviderError
        }
    }
}
