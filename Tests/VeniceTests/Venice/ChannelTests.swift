import XCTest
import Venice

struct Fou {
    let bar: Int
    let baz: Int
}

public class ChannelTests : XCTestCase {
    func testCreationOnCanceledCoroutine() throws {
        let coroutine = try Coroutine {
            try Coroutine.yield()
            XCTAssertThrowsError(try Channel<Void>(), error: VeniceError.canceledCoroutine)
        }

        coroutine.cancel()
    }

    func testSendOnCanceledCoroutine() throws {
        let channel = try Channel<Void>()

        let coroutine = try Coroutine {
            XCTAssertThrowsError(
                try channel.send(deadline: .never),
                error: VeniceError.canceledCoroutine
            )
        }

        coroutine.cancel()
    }

    func testSendOnDoneChannel() throws {
        let channel = try Channel<Void>()
        channel.done()

        XCTAssertThrowsError(try channel.send(deadline: .never), error: VeniceError.doneChannel)
    }

    func testSendTimeout() throws {
        let channel = try Channel<Int>()

        XCTAssertThrowsError(try channel.send(111, deadline: .immediately), error: VeniceError.deadlineReached)

        let coroutine = try Coroutine {
            try channel.send(222, deadline: .never)
        }

        XCTAssertEqual(try channel.receive(deadline: .never), 222)
        coroutine.cancel()
    }

    func testDoubleSendTimeout() throws {
        let channel = try Channel<Int>()

        let coroutine1 = try Coroutine {
            XCTAssertThrowsError(
                try channel.send(111, deadline: 50.milliseconds.fromNow()),
                error: VeniceError.deadlineReached
            )
        }

        let coroutine2 = try Coroutine {
            XCTAssertThrowsError(
                try channel.send(222, deadline: 50.milliseconds.fromNow()),
                error: VeniceError.deadlineReached
            )
        }

        try Coroutine.wakeUp(100.milliseconds.fromNow())

        let coroutine3 = try Coroutine {
            try channel.send(333, deadline: .never)
        }

        XCTAssertEqual(try channel.receive(deadline: .never), 333)

        coroutine1.cancel()
        coroutine2.cancel()
        coroutine3.cancel()
    }

    func testReceiveOnCanceledCoroutine() throws {
        let channel = try Channel<Void>()

        let coroutine = try Coroutine {
            XCTAssertThrowsError(
                try channel.receive(deadline: .never),
                error: VeniceError.canceledCoroutine
            )
        }

        coroutine.cancel()
    }

    func testReceiveOnDoneChannel() throws {
        let channel = try Channel<Void>()
        channel.done()
        XCTAssertThrowsError(try channel.receive(deadline: .never), error: VeniceError.doneChannel)
    }

    func testReceiveTimeout() throws {
        let channel = try Channel<Int>()

        XCTAssertThrowsError(
            try channel.receive(deadline: .immediately),
            error: VeniceError.deadlineReached
        )

        let coroutine = try Coroutine {
            XCTAssertEqual(try channel.receive(deadline: .never), 222)
        }

        try channel.send(222, deadline: .never)
        coroutine.cancel()
    }

    func testReceiverWaitsForSender() throws {
        let channel = try Channel<Int>()

        let coroutine = try Coroutine {
            XCTAssertEqual(try channel.receive(deadline: .never), 333)
        }

        try channel.send(333, deadline: .never)
        coroutine.cancel()
    }

    func testSenderWaitsForReceiver() throws {
        let channel = try Channel<Int>()

        let coroutine = try Coroutine {
            try channel.send(444, deadline: .never)
        }

        XCTAssertEqual(try channel.receive(deadline: .never), 444)
        coroutine.cancel()
    }

    func testSendingChannel() throws {
        let channel = try Channel<Int>()

        func send(to channel: Channel<Int>.Sending) throws {
            try channel.send(111, deadline: .never)
        }

        let coroutine = try Coroutine {
            try send(to: channel.sending)
        }

        XCTAssertEqual(try channel.receive(deadline: .never), 111)
        coroutine.cancel()
    }

    func testSendErrorToSendingChannel() throws {
        let channel = try Channel<Int>()

        func send(to channel: Channel<Int>.Sending) throws {
            try channel.send(VeniceError.unexpectedError, deadline: .never)
        }

        let coroutine = try Coroutine {
            try send(to: channel.sending)
        }

        XCTAssertThrowsError(try channel.receive(deadline: .never), error: VeniceError.unexpectedError)
        coroutine.cancel()
    }

    func testDoneOnDoneSendingChannel() throws {
        let channel = try Channel<Void>()
        let sending = channel.sending
        channel.done()
        sending.done()
    }

    func testReceivingChannel() throws {
        let channel = try Channel<Int>()

        func receive(_ channel: Channel<Int>.Receiving) {
            XCTAssertEqual(try channel.receive(deadline: .never), 999)
        }

        let coroutine = try Coroutine {
            try channel.send(999, deadline: .never)
        }

        receive(channel.receiving)
        coroutine.cancel()
    }

    func testDoneOnDoneReceivingChannel() throws {
        let channel = try Channel<Void>()
        let receiving = channel.receiving
        channel.done()
        receiving.done()
    }

    func testTwoSimultaneousSenders() throws {
        let channel = try Channel<Int>()

        let coroutine1 = try Coroutine {
            try channel.send(888, deadline: .never)
        }

        let coroutine2 = try Coroutine {
            try channel.send(999, deadline: .never)
        }

        XCTAssertEqual(try channel.receive(deadline: .never), 888)
        XCTAssertEqual(try channel.receive(deadline: .never), 999)

        coroutine1.cancel()
        coroutine2.cancel()
    }

    func testTwoSimultaneousReceivers() throws {
        let channel = try Channel<Int>()

        let coroutine1 = try Coroutine {
            XCTAssertEqual(try channel.receive(deadline: .never), 333)
        }

        let coroutine2 = try Coroutine {
            XCTAssertEqual(try channel.receive(deadline: .never), 444)
        }

        try channel.send(333, deadline: .never)
        try channel.send(444, deadline: .never)

        coroutine1.cancel()
        coroutine2.cancel()
    }

    func testTypedChannels() throws {
        let stringChannel = try Channel<String>()

        let coroutine1 = try Coroutine {
            try stringChannel.send("yo", deadline: .never)
        }

        XCTAssertEqual(try stringChannel.receive(deadline: .never), "yo")

        let fooChannel = try Channel<Fou>()

        let coroutine2 = try Coroutine {
            try fooChannel.send(Fou(bar: 555, baz: 222), deadline: .never)
        }

        let foo = try fooChannel.receive(deadline: .never)
        XCTAssertEqual(foo.bar, 555)
        XCTAssertEqual(foo.baz, 222)

        coroutine1.cancel()
        coroutine2.cancel()
    }

    func testDoneChannelUnblocks() throws {
        let channel1 = try Channel<Int>()
        let channel2 = try Channel<Int>()

        let coroutine1 = try Coroutine {
            XCTAssertThrowsError(
                try channel1.receive(deadline: .never),
                error: VeniceError.doneChannel
            )

            try channel2.send(0, deadline: .never)
        }

        let coroutine2 = try Coroutine {
            XCTAssertThrowsError(
                try channel1.receive(deadline: .never),
                error: VeniceError.doneChannel
            )

            try channel2.send(0, deadline: .never)
        }

        channel1.done()

        XCTAssertEqual(try channel2.receive(deadline: .never), 0)
        XCTAssertEqual(try channel2.receive(deadline: .never), 0)

        coroutine1.cancel()
        coroutine2.cancel()
    }

    func testTenThousandWhispers() throws {
        self.measure {
            do {
                let numberOfWhispers = 10_000
                let whispers = Coroutine.Group(minimumCapacity: numberOfWhispers)

                let leftmost = try Channel<Int>()

                var right = leftmost
                var left = leftmost

                for _ in 0 ..< numberOfWhispers {
                    right = try Channel<Int>()

                    try whispers.addCoroutine {
                        try left.send(right.receive(deadline: .never) + 1, deadline: .never)
                    }

                    left = right
                }

                let starter = try Coroutine {
                    try right.send(1, deadline: .never)
                }

                XCTAssertEqual(try leftmost.receive(deadline: .never), numberOfWhispers + 1)

                starter.cancel()
                whispers.cancel()
            } catch {
                XCTFail()
            }
        }
    }
}

extension ChannelTests {
    public static var allTests: [(String, (ChannelTests) -> () throws -> Void)] {
        return [
            ("testCreationOnCanceledCoroutine", testCreationOnCanceledCoroutine),
            ("testSendOnCanceledCoroutine", testSendOnCanceledCoroutine),
            ("testSendOnDoneChannel", testSendOnDoneChannel),
            ("testSendTimeout", testSendTimeout),
            ("testReceiveOnCanceledCoroutine", testReceiveOnCanceledCoroutine),
            ("testReceiveOnDoneChannel", testReceiveOnDoneChannel),
            ("testReceiveTimeout", testReceiveTimeout),
            ("testReceiverWaitsForSender", testReceiverWaitsForSender),
            ("testSenderWaitsForReceiver", testSenderWaitsForReceiver),
            ("testSendingChannel", testSendingChannel),
            ("testDoneOnDoneSendingChannel", testDoneOnDoneSendingChannel),
            ("testReceivingChannel", testReceivingChannel),
            ("testTwoSimultaneousSenders", testTwoSimultaneousSenders),
            ("testTwoSimultaneousReceivers", testTwoSimultaneousReceivers),
            ("testTypedChannels", testTypedChannels),
            ("testDoneChannelUnblocks", testDoneChannelUnblocks),
            ("testTenThousandWhispers", testTenThousandWhispers),
        ]
    }
}
