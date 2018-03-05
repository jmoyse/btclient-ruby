require 'io/nonblock'
include Socket::Constants

class Server
	attr_accessor :seeding, :peers, :torrent
	
	#def initialize(id,port,piecesList,torrentMetadata,torrentHash)
	def initialize(tracker)
		@waitingPeers = Array.new
		@startTime = Time.now
		@sockets = Array.new
		@peers = Array.new
				
		@tracker = tracker
		@client_id = @tracker.peerID
		@outgoingPort = @tracker.port
		@piecesList = @tracker.piecesList
		@torrentMetadata = @tracker.torrent.torrentMetadata
		@torrentHash = @tracker.torrent.completeHash
		@seeding = @tracker.completed
		throttleSpeed(false)
	end

	
	def addNewPeer(peer_ip, peer_port,peer_id)
		if peer_ip == nil|| peer_port== nil || peer_id == nil
			return
		end
		peer = Peer.new(peer_ip,peer_port,peer_id, @client_id, createBitfield(), @torrentMetadata,@torrentHash)
		peer.openConnection()
		if peer.valid == false
			return
		end
		if isDuplicateConnection(peer_ip,peer_port) 
			puts debugMessage("#{peer} Peer attempting duplicate connection")
		end
		peer.handshake(true)
		
		
		if peer.valid && peer.socket!=nil
			@peers.push(peer)
			@sockets.push(peer.socket)
		end
	end
	
	# Adds a new peer object to the torrent server
	def addPeer(peer)
		if peer == nil
			puts debugMessage("ERROR: Bad peer data.  Removing from system")
			return 
		end
		@peers.push(peer)
		@sockets.push(peer.socket)
	end
	
	
	def isDuplicateConnection(ip,port)
		found = false
		@peers.each{ |peer|
			if peer.ip==ip &&peer.port == port
				return true
			end		
		}
		return found
	end
	
	
	def updateWaitingQueue()
		# add anybody new to the queue
		@peers.each{ |peer|
			if peer!=nil && peer.queue!= nil && peer.queue.length > 0 
				if !(@waitingPeers.include?(peer))
					@waitingPeers.push(peer)
				end
			end		
		}
		
		# remove any old ones
		@waitingPeers.each{|peer|
			if peer.queue == nil || peer.queue.length < 0
				@waitingPeer.remove(peer)
			end
		}
	end
	
	def sendQueue()	
		updateWaitingQueue()  # make sure our queue is accurate
		if @waitingPeers.length<=0
			return
		end
		totalSent = 0
		if @rateLimit == true
			peer = @waitingPeers.shift
			totalSent+=peer.sendPacket(0)
			
			if peer.queue.length > 0
				@waitingPeers.push(peer)
			end
		else 
			while(@waitingPeers.length > 0)
				peer = @waitingPeers.shift
				totalSent+=peer.sendPacket(0)
				
				if peer.queue.length > 0
					@waitingPeers.push(peer)
				end
			
			end
		end
	end
  
	# Starts a new torrent server.  Creates a port on the outgoing port
	# and waits for any connects coming on the incoming port
	def startNewServer
		begin 
			@outgoingSocket = TCPServer.new("",@outgoingPort)			
			#@outgoingSocket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
			@outgoingSocket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, 1)
			@outgoingSocket.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
			#@outgoingSocket.bind(Socket.sockaddr_in(@outgoingPort, 'localhost'))
			@sockets.push(@outgoingSocket)
		rescue Exception => e 
			puts debugMessage("Error openning torrent port.  Port in use perhaps? #{e}");
		end
		
		while true
			$stdout.flush
			checkForPeers()
			checkPeerIntegrity()		
			
			selected = select(@sockets,nil,nil, @selectTimeout)
			if selected == nil
				sendQueue()
			else
				for socket in selected[0]
					if socket == @outgoingSocket
						##Dputs "New peer attemping to connect"
						receiveClient()
					elsif @sockets.include?(socket)
						if socket.eof?
							peer = peer_by_socket(socket)
							#peer.openConnection()
							#peer.handshake(true)
							removePeer(peer, "Connection closed by peer")
						else
							receiveMessage(socket)
						end
					else
						puts "Not too sure about this error"
					end
				end
			end
			checkDownloadStatus()	
		end
	end
		
	
	# Logic to handle what happens we a new message is received
	def receiveMessage(socket)
		# Check that the socket is okay
		if socket == nil
			puts 
			puts debugMessage("[#{peer}]: Error Receiving Message.  Bad Socket")
			return
		end
		begin
			socket_ip = socket.peeraddr[3]
			peer = peer_by_socket(socket)
		rescue StandardError => e
			#puts "Receive error #{e}"
			#peer = peer_by_socket(socket)
			#peer.valid = false
			return
		end

		
		# messagePrefixRaw = ""
		# begin
			# messagePrefixRaw << socket.read_nonblock(4)
		# rescue Errno::EWOULDBLOCK
			# if IO.select([socket], nil, nil, 2)
				# messagePrefixRaw << socket.read_nonblock(4)
			# else
				# raise Timeout::TimeoutError
			# end
		# end
		
		#messagePrefixRaw = socket.read(4)
		
		messagePrefixRaw = peer.readFromSocket(4)
		
		if messagePrefixRaw==nil || messagePrefixRaw.length == 0
			puts debugMessage("[#{peer}]: Payload Size Error.  Aborting read")
			return
		end
		
		messagePrefix = messagePrefixRaw.unpack('N')[0]
		
		#message = socket.read(messagePrefix)
		message = peer.readFromSocket(messagePrefix)
		if (message == nil || message.length == 0)
			puts debugMessage("[#{peer}]: Message Read Error.  Dropping packet")
			return
		end
		
		messageID = message.unpack('C')[0].to_i
	
		# Grab and unpack the message			
		if messagePrefix == 0 # ID:0 Keep alive
			peer.lastConnected = Time.now
			peer.keepAlive() # send keep alive back
			puts debugMessage("[#{peer}]: Got Keep Alive")
		elsif messagePrefix == 1 && messageID==0 # Prefix:1 & ID:0 Choke
			peer.peer_choking = true
			puts debugMessage("[#{peer}]: Got Choke")
		elsif messagePrefix == 1 && messageID==1 # Prefix:1 & ID:1 Unchoke
			peer.peer_choking = false
			puts debugMessage("[#{peer}]: Got Unchoked")
		elsif messagePrefix == 1 && messageID==2 # Prefix:1 & ID:2 Interested
			puts debugMessage("[#{peer}]: Got Interested")
			peer.peer_interested = true
			if (activePeerCount < 50)
				peer.sendUnchoke()
			else	
				peer.sendChoke()
			end
		elsif messagePrefix == 1 && messageID==3 # Prefix:1 & ID:3 Not Interested
			puts debugMessage("[#{peer}]: Got Not Interested")
			peer.sendChoke()
			peer.peer_interested = false
		elsif messagePrefix == 5 && messageID == 4 # Prefix:5 & ID:4 Have
			pieceNumber = message.unpack('CN')[1].to_i
			peer.addPiece(@piecesList[pieceNumber])
			puts debugMessage("[#{peer}]: Got Have #{pieceNumber}")
		elsif messagePrefix>1 && messageID == 5 # Prefix > 1 & ID:5 Bitfield
			bits = message[1..message.length].unpack('B*')[0]
			@piecesList.length.times{ |pieceNumber|
				bit = bits[pieceNumber].chr
				if bit == '1'
					peer.addPiece(@piecesList[pieceNumber])
				end
			}
			puts debugMessage("[#{peer}]: Got Bitfield #{peer.getBlocks()}")			
		elsif messagePrefix == 13 && messageID == 6 # Prefix:13 & ID:6 Request			
			command = message[0,1]
			indexPoint =  message[1,4].to_s.unpack('N')
			beginPoint =  message[5,4].to_s.unpack('N')
			messageLen = message[9,4].to_s.unpack('N')
			
			puts debugMessage("[#{peer}]: Got Request #{indexPoint}:#{beginPoint}->#{beginPoint.to_s.to_i+messageLen.to_s.to_i}")
			
			dataBlock = @piecesList[indexPoint.to_s.to_i].getBlock(beginPoint.to_s.to_i,messageLen.to_s.to_i)
			peer.sendPiece(dataBlock, indexPoint, beginPoint)	
		elsif messagePrefix > 9 && messageID == 7 && peer.filePiece!=nil # Prefix>9 & ID:7 Piece
			command = message[0,1]
			indexPoint =  message[1,4].to_s.unpack('N')
			beginPoint =  message[5,4].to_s.unpack('N')
			payload = message[9,message.length-9]

			peer.filePiece.append(payload,indexPoint,beginPoint)
			
			if !peer.filePiece.complete # TODO: Allow blocks within a piece to be downloaded in non-linear order
				peer.requestBlock(beginPoint.to_s.to_i+payload.length)

			end
			peer.updateTime = Time.now
		elsif messagePrefix == 13 && messageID<=8 # Prefix:13 & ID<=8 Cancel
			#puts "cancel"
		elsif messagePrefix == 3 && messageID== 9 # Prefix:3 & ID:9 Port
			#puts "port"
		else
			puts debugMessage("[#{peer}]: Received unknown message ID #{messageID} with prefix #{messagePrefix}")
		end
	end
	

	# Received a connect request from a new client.  
	def receiveClient()
		
		return if @outgoingSocket == nil		
		begin
			@outgoingSocket.listen(999)
			socket = @outgoingSocket.accept
			socket.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
		rescue StandardError=>e	#, Errno::EAGAIN, Errno::ECONNABORTED, Errno::EINTR, Errno::EWOULDBLOCK
			puts debugMessage("Error Connecting creating connection to peer: #{e}")
			#IO.select([@outgoingSocket])
			#retry
			return
		end
				
		peerIP = socket.peeraddr[3]
		peerPort = socket.peeraddr[1]
		puts debugMessage("Incoming connection request from #{peerIP}:#{peerPort}")
		peer = Peer.new(peerIP,peerPort, nil, @client_id, createBitfield(), @torrentMetadata,@torrentHash)
		
		# TODO: refactor this.  its basically the same as addnewpeer
		peer.socket = socket
		peer.handshake(false)
		
		if peer.valid && peer.socket!=nil
			puts debugMessage("[#{peer}]: Peer Connected")
			@peers.push(peer)
			@sockets.push(peer.socket)
		end
		#socket.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
	end
	
	# Add each peers count to the hash, and determine the rarest pieces
	def getRarityHash()
		rarityHash = Hash.new
		@piecesList.each{|pieceNumber|
			rarityHash[pieceNumber] = 0
		}
		
		@peers.each{ |peer|
			peer.has.each{|piece|
				if piece!= nil && piece!=false				
					rarityHash[piece]+=1
				end
			}
		}
		return rarityHash
	end
	
	# Removes the offending peer from the system
	def removePeer(peer, message="Peer Disconnected")
		if peer!=nil
			peer.filePiece = nil
			@sockets.delete(peer.socket)
			@peers.delete(peer)
			if peer!=nil && peer.socket!=nil && !peer.socket.closed?
				peer.socket.close
			end
			puts debugMessage("[#{peer.to_s()}]: #{message}")
		end
	end
	
	# Finds the peer object associated with a socket
	def peer_by_socket(socket)
		@peers.each{|peer|
			if peer.socket == socket
				return peer
			end
		}
		return nil
	end
	
	# Checks how many files are.  If they're all complete, does a file SHA1 checksum
	def checkDownloadStatus()
		if @seeding == true
			return
		end
	
		allDownloaded = true
		finishedCount=0
		@piecesList.each{ |piece|
			if piece.complete!=true
				allDownloaded = false
			else 
				finishedCount+=1
			end
		}
		
		if allDownloaded == true #&& finishedCount == @torrentMetadata["info"]["pieces"]
			@piecesList.each{ |piece|
				if !piece.checkHash() # Theres a bad piece.
					puts debugMessage("Download complete, but there is fails checksum")
					return
				end
			}
			transferRate = (((@torrent.totalPieces)/(Time.now-@startTime))/1000).to_s
			puts debugMessage("Download completed in #{Time.now-@startTime}s [#{transferRate.to_s.gsub(/(\d)(?=\d{3}+(\.\d*)?$)/, '\1,')} KB/sec]")
			puts debugMessage("Seed Process Started")
			 
			@seeding = true
		end
	end
	
	# Make sure we have some peers.  If not, we exit
	def checkForPeers()
		if @peers.length == 0
			#puts "No more peers :("
			#exit(1)
		end
	end
	
	# Cleanup any bad peers and do the choking checks
	def checkPeerIntegrity()
		checkDownloadStatus()
		@peers.each {|peer|
			if peer.valid == false
				removePeer(peer)
			end
			
			if @seeding != true  # these dont need to be checked if we're seeding
			
				if peer.filePiece && peer.filePiece.complete # Peer finished downloading file. Remove it and attempt to get another
					##puts "Finished Piece #{peer.filePiece.segment_number}"
					notifyPeers(peer.filePiece.segment_number)
					peer.filePiece.complete = true
					peer.filePiece = false
				end

				if peer.peer_choking == true && (Time.now - peer.interestedRequestTime) > 120 # only second an interested every time period
					peer.sendInterested()
				end

				if peer.peer_choking == false && (!peer.filePiece  || peer.filePiece.complete)
					peer.filePiece = nil
					piecePriority = getRarityHash()
					piece = peer.getRarestPiece(piecePriority)
					if piece!=nil
						puts debugMessage("[#{peer.to_s}]: Assigned Piece #{piece.segment_number}")
						peer.assignPiece(piece)
					else
						#puts "Error finding piece"
					end
				end
			else # we are seeding
				if peer.isSeeding && peer.isSeeding != "invalidPeer"# we're both seeding, no reason to keep the peer
					puts debugMessage("[#{peer.to_s}]: Is Seeder.  Disconnecting")
					peer.isSeeding = "invalidPeer"
					peer.sendNotInterested()
					peer.valid = false
				end
				
			end
			
		}
	end
	
	def notifyPeers(pieceNo)
		@peers.each{ |peer|
			peer.sendHave(pieceNo)
		}
	end
	
	# The number of active peers
	def activePeerCount()
		return  @peers.length
	end
	
	# Create a listing of the completed fields we have
	def createBitfield()
		bitfield = []
		
		@piecesList.each{ |piece|
			if piece.complete == true
				bitfield.push('1')
			else			
				bitfield.push('0')
			end
		}
		remainderBits = @piecesList.length%8
		
		
		if remainderBits > 0
			remainderBits = 8 - remainderBits
			remainderBits.times{ 
				bitfield.push('0')
			}
		end

		return bitfield		
	end
	
	def getDataBlock(indexPoint,beginPoint,msgLength)
		@piecesList.each{ |piece|
			if piece.segment_number == indexPoint
				piece.getBlock(beginPoint,msgLength)
			end
		}
	end	
	
	def throttleSpeed(value)
		if value == true
			puts debugMessage("Upload & download transfer speed throttled to 8KB/sec")
			@rateLimit = true
			@selectTimeout = 2 # the amount of time that can pass before 16 kilobytes can be sent
		else
			puts debugMessage("Upload & download transfer speed unthrottled")
			@rateLimit = false
			@selectTimeout = 0.001
		end
	end
	
	def debugMessage(message)
		time = Time.now;
		return "[#{time.strftime("%X")}] #{message}"
	end
	
end
