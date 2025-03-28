//
// Copyright (c) 2021-2024. NICE Ltd. All rights reserved.
//
// Licensed under the NICE License;
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    https://github.com/nice-devone/nice-cxone-mobile-sdk-ios/blob/main/LICENSE
//
// TO THE EXTENT PERMITTED BY APPLICABLE LAW, THE CXONE MOBILE SDK IS PROVIDED ON
// AN “AS IS” BASIS. NICE HEREBY DISCLAIMS ALL WARRANTIES AND CONDITIONS, EXPRESS
// OR IMPLIED, INCLUDING (WITHOUT LIMITATION) WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, AND TITLE.
//

import Foundation

/// The initial decoding of a message from the WebSocket.
struct GenericEventDTO: Decodable, Equatable {
    
    // MARK: - Properties
    
    /// Event ID of this event (or original event we're responding to)
    let eventId: LowerCaseUUID?
    /// The type of the event.
    let eventType: EventType?
    /// The postback of the event.
    let postback: GenericEventPostbackDTO?
    let error: OperationError?
    let internalServerError: InternalServerError?

    // MARK: - Init
    
    init(
        eventId: LowerCaseUUID? = nil,
        eventType: EventType?,
        postback: GenericEventPostbackDTO?,
        error: OperationError?,
        internalServerError: InternalServerError?
    ) {
        self.eventId = eventId
        self.eventType = eventType
        self.postback = postback
        self.error = error
        self.internalServerError = internalServerError
    }
}

// MARK: - ReceivedEvent

extension GenericEventDTO: ReceivedEvent {
    static let eventType: EventType? = nil

    var postbackEventType: EventType? { postback?.eventType }
}
