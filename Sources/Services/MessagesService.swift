import Foundation


class MessagesService: MessagesProvider {
    
    // MARK: - Properties
    
    private let contactFieldsProvider: ContactCustomFieldsProvider
    private let customerFieldsProvider: CustomerCustomFieldsProvider
    private var connectionContext: ConnectionContext { socketService.connectionContext }
    
    let socketService: SocketService
    let eventsService: EventsService
    
    
    // MARK: - Init
    
    init(
        contactFieldsProvider: ContactCustomFieldsProvider,
        customerFieldsProvider: CustomerCustomFieldsProvider,
        socketService: SocketService,
        eventsService: EventsService
    ) {
        self.contactFieldsProvider = contactFieldsProvider
        self.customerFieldsProvider = customerFieldsProvider
        self.socketService = socketService
        self.eventsService = eventsService
    }
    
    
    // MARK: - Implementation
    
    /// - Throws: ``CXoneChatError/notConnected`` if an attempt was made to use a method without connecting first.
    ///     Make sure you call the `connect` method first.
    /// - Throws: ``CXoneChatError/noMoreMessages`` if there aren't any other messages, so additional messages could not be loaded.
    /// - Throws: ``CXoneChatError/invalidOldestDate`` if Thread is missing the timestamp of when the message was created.
    /// - Throws: ``CXoneChatError/customerAssociationFailure`` if the SDK could not get customer identity and it may not have been set.
    /// - Throws: ``EncodingError.invalidValue(_:_:)`` if the given value is invalid in the current context for this format.``
    func loadMore(for chatThread: ChatThread) throws {
        LogManager.trace("Loading more messages.")

        try socketService.checkForConnection()

        guard chatThread.hasMoreMessagesToLoad else {
            throw CXoneChatError.noMoreMessages
        }
        guard let oldestDate = chatThread.messages.first?.createdAt else {
            throw CXoneChatError.invalidOldestDate
        }

        let thread = ThreadDTO(idOnExternalPlatform: chatThread.id, threadName: chatThread.name)
        let data = try eventsService.create(
            .loadMoreMessages,
            with: .loadMoreMessageData(LoadMoreMessagesEventDataDTO(scrollToken: chatThread.scrollToken, thread: thread, oldestMessageDatetime: oldestDate))
        )
        
        socketService.send(message: data.utf8string)
    }
    
    /// - Throws: ``CXoneChatError/notConnected`` if an attempt was made to use a method without connecting first.
    ///     Make sure you call the `connect` method first.
    /// - Throws: ``CXoneChatError/customerAssociationFailure`` if the SDK could not get customer identity and it may not have been set.
    /// - Throws: ``EncodingError.invalidValue(_:_:)`` if the given value is invalid in the current context for this format.
    func send(_ message: String, for chatThread: ChatThread) async throws {
        try await send(OutboundMessage(text: message), for: chatThread)
    }
    
    /// - Throws: ``CXoneChatError/notConnected`` if an attempt was made to use a method without connecting first.
    ///     Make sure you call the `connect` method first.
    /// - Throws: ``CXoneChatError/customerAssociationFailure`` if the SDK could not get customer identity and it may not have been set.
    /// - Throws: ``CXoneChatError/missingParameter(_:)`` if attachments upload `url` has not been set properly or attachment uploaded data object is missing.
    /// - Throws: ``CXoneChatError/serverError`` if the server experienced an internal error and was unable to perform the action.
    /// - Throws: ``CXoneChatError/attachmentError`` if the provided attachment was unable to be sent.
    /// - Throws: ``EncodingError.invalidValue(_:_:)`` if the given value is invalid in the current context for this format.
    /// - Throws: ``URLError.badServerResponse`` if the URL Loading system received bad data from the server.
    /// - Throws: ``NSError`` object that indicates why the request failed
    /// - Throws: An error in the Cocoa domain, if `url` cannot be read.
    func send(_ message: String, with attachments: [ContentDescriptor], for chatThread: ChatThread) async throws {
        try await send(OutboundMessage(text: message, attachments: attachments), for: chatThread)
    }
    
    /// - Throws: ``CXoneChatError/notConnected`` if an attempt was made to use a method without connecting first.
    ///     Make sure you call the `connect` method first.
    /// - Throws: ``CXoneChatError/customerAssociationFailure`` if the SDK could not get customer identity and it may not have been set.
    /// - Throws: ``CXoneChatError/missingParameter(_:)`` if attachments upload `url` has not been set properly or attachment uploaded data object is missing.
    /// - Throws: ``CXoneChatError/serverError`` if the server experienced an internal error and was unable to perform the action.
    /// - Throws: ``CXoneChatError/attachmentError`` if the provided attachment was unable to be sent.
    /// - Throws: ``EncodingError.invalidValue(_:_:)`` if the given value is invalid in the current context for this format.
    /// - Throws: ``URLError.badServerResponse`` if the URL Loading system received bad data from the server.
    /// - Throws: ``NSError`` object that indicates why the request failed
    /// - Throws: An error in the Cocoa domain, if `url` cannot be read.
    @discardableResult
    func send(_ message: OutboundMessage, for chatThread: ChatThread) async throws -> Message {
        LogManager.trace("Sending a message in the specified chat thread.")

        try socketService.checkForConnection()

        let contactFields = (contactFieldsProvider as? ContactCustomFieldsService)?.contactFields[chatThread.id]?.compactMap { field -> CustomFieldDTO? in
            guard let value = field.value, !value.isEmpty else {
                return nil
            }
            
            return CustomFieldDTO(ident: field.ident, value: value, updatedAt: field.updatedAt)
        } ?? []
        let customerFields = (customerFieldsProvider as? CustomerCustomFieldsService)?.customerFields.compactMap { field -> CustomFieldDTO? in
            guard let value = field.value, !value.isEmpty else {
                return nil
            }
            
            return CustomFieldDTO(ident: field.ident, value: value, updatedAt: field.updatedAt)
        } ?? []
        let mappedAttachments = try await message.attachments.map(with: connectionContext)
        
        let eventData = EventDataType.sendMessageData(
            SendMessageEventDataDTO(
                thread: ThreadDTO(idOnExternalPlatform: chatThread.id, threadName: chatThread.name),
                contentType: .text(MessagePayloadDTO(text: message.text, postback: message.postback)),
                idOnExternalPlatform: UUID(),
                customer: CustomerCustomFieldsDataDTO(customFields: customerFields),
                contact: ContactCustomFieldsDataDTO(customFields: contactFields),
                attachments: mappedAttachments,
                deviceFingerprint: DeviceFingerprintDTO(deviceToken: connectionContext.deviceToken),
                token: socketService.accessToken.map(\.token)
            )
        )
        
        let data = try eventsService.create(.sendMessage, with: eventData)
        
        socketService.send(message: data.utf8string)
        
        return Message(
            id: UUID(),
            threadId: chatThread.id,
            contentType: .text(MessagePayload(text: message.text, postback: message.postback)),
            createdAt: Date(),
            attachments: mappedAttachments.map(AttachmentMapper.map),
            direction: .toAgent,
            userStatistics: nil,
            authorUser: chatThread.assignedAgent,
            authorEndUserIdentity: connectionContext.customer.map(CustomerIdentityMapper.map)
        )
    }
}


// MARK: - ContentDescriptor Mapper

private extension [ContentDescriptor] {
    
    /// - Throws: ``CXoneChatError/serverError`` if the server experienced an internal error and was unable to perform the action.
    /// - Throws: ``CXoneChatError/missingParameter(_:)`` if attachments upload `url` has not been set properly or attachment uploaded data object is missing.
    /// - Throws: ``EncodingError.invalidValue(_:_:)`` if the given value is invalid in the current context for this format.
    /// - Throws: ``CXoneChatError/attachmentError`` if the provided attachment was unable to be sent.
    /// - Throws: ``URLError.badServerResponse`` if the URL Loading system received bad data from the server.
    /// - Throws: ``NSError`` object that indicates why the request failed
    /// - Throws: An error in the Cocoa domain, if `url` cannot be read.
    func map(with connectionContext: ConnectionContext) async throws -> [AttachmentDTO] {
        let chatURL = connectionContext.environment.chatURL
        let brandId = connectionContext.brandId
        let channelId = connectionContext.channelId
        
        guard let url = URL(string: "\(chatURL)/1.0/brand/\(brandId)/channel/\(channelId)/attachment") else {
            throw CXoneChatError.missingParameter("url")
        }
        
        var request = URLRequest(url: url, method: .post, contentType: "application/json")

        let returned = try await self.asyncMap { attachment in
            request.httpBody = try await JSONEncoder().encode([
                "content": attachment.data.fetch().base64EncodedString(),
                "fileName": attachment.fileName,
                "mimeType": attachment.mimeType
            ])
            
            let (data, response) = try await connectionContext.session.data(for: request)
            
            guard let response = response as? HTTPURLResponse, (200 ... 299) ~= response.statusCode else {
                throw CXoneChatError.serverError
            }
            guard let decoded: AttachmentUploadSuccessResponseDTO = try data.decode() else {
                throw CXoneChatError.missingParameter("decodedData")
            }
            
            return AttachmentDTO(
                url: decoded.fileUrl,
                friendlyName: attachment.friendlyName,
                mimeType: attachment.mimeType,
                fileName: attachment.fileName
            )
        }
        
        guard returned.count >= self.count else {
            throw CXoneChatError.attachmentError
        }
        
        return returned
    }
}


// MARK: - Helpers

private extension URL {
    
    /// - Throws: ``CXoneChatError/noSuchFile`` if an attached file could not be found.
    /// - Throws: An error in the Cocoa domain, if `url` cannot be read.
    func readSecureData() async throws -> Data {
        guard startAccessingSecurityScopedResource() else {
            throw CXoneChatError.noSuchFile(absoluteString)
        }
        defer {
            stopAccessingSecurityScopedResource()
        }

        return try Data(contentsOf: self)
    }
}

private extension ContentDescriptorSource {
    
    /// - Throws: An error in the Cocoa domain, if `url` cannot be read.
    func fetch() async throws -> Data {
        switch self {
        case .bytes(let data):
            return data
        case .uri(let uri):
            if uri.isStoredInDocuments() {
                return try Data(contentsOf: uri)
            }
            
            return try await uri.readSecureData()
        }
    }
}

private extension URL {
    
    func isStoredInDocuments() -> Bool {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return false
        }
        
        return absoluteString.starts(with: documentsURL.absoluteString)
    }
}
