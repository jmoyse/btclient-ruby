require 'FilePiece.rb'
require 'digest/sha1'
require 'net/http'
require 'cgi'
require 'socket'
require 'Server.rb'

begin
require 'io/nonblock'
rescue LoadError
	puts "error: io/nonblock not found."
end

class Peer
	attr_accessor :queue,:id, :port, :ip, :clientID,:has, :lastConnected, :socket, :am_choking, :am_interested, :peer_choking, :peer_interested, :filePiece, :interestedRequestTime, :valid, :updateTime, :isSeeding
	
	def initialize(ip,port,id,clientID,bitfield,torrentMetadata,completeHash)
		if id == nil
			@id = ""
		else 
			@id = id
		end
		
		@port = port
		@ip = ip
		@queue =  Array.new
		@updateTime = Time.now
		@valid = true
		@clientID = clientID
		@bitfield = bitfield # TODO: find a better way to do this bitfield thing
		@torrentMetadata = torrentMetadata
		@completeHash = completeHash
		@isSeeding = false
		@completeCount = 0
		
		@packetSent = Time.now - 500 # make sure we can start sending right away
		@am_choking = true
		@am_interested = false
		@peer_choking = true
		@peer_interested = false		
		
		@interestedRequestTime = Time.now - 250
		@requestSize = 16384

		pieceCount =(torrentMetadata["info"]["pieces"].length/20).to_i
		@has = Array.new(pieceCount)
		
		pieceCount.times{ |pieceNumber|
			@has[pieceNumber] = false
		}
		updateTime()
	end
	
	def openConnection()
		
		begin
			timeout(5) do
				@socket = TCPSocket.open(@ip, @port)
				#@socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM)
				@socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
				@socket.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
			end
		
			if @socket == nil
				puts debugMessage("[#{to_s()}]: Error Opening Connection")
				@valid == false			
			end
		rescue Exception => e
			#puts "Socket Open Error: #{e}"
			puts debugMessage("[#{to_s()}]: Unreachable Peer")
			@valid = false
		end
	end
	
	def updateTime()
		@lastConnected = Time.now
	end


	def sendPacket(amount)
		if @queue==nil || @queue.length == 0 #@amountSent >= @allowed
			return
		end
		
		packet = @queue.first
		msg = packet[0]
		
		if amount == 0
			packet = @queue.shift
			msgToSend = packet[0]
		elsif amount > msg.length 
			packet = @queue.shift
			msgToSend = packet[0]			
		else
			msgToSend= msg.slice!(amount)
		end
		
		sent = -1

		sent = @socket.send(msgToSend,0)
		puts debugMessage("#{packet[1]}")
		puts debugMessage("[#{to_s()}]: Sent #{sent} bytes")
		
		
		return sent
	end
	
	
	def queuePacket(packet,message)
		if packet == nil 
			return
		end
		@queue.push([packet,message])		
	end
	
	def peer_choking=(status)
		if status == true || status == false
			@peer_choking = status
		end
	end	
	
	def assignPiece(filePiece)
		if filePiece == nil 
			return nil
		end
		@filePiece = filePiece
		requestPiece()
	end

	def requestBlock(startPos)
		if @filePiece.position >= @filePiece.pieceLength 
			@filePiece.complete = true
			return
		else
			length = @requestSize
			if (@filePiece.pieceLength) > (@requestSize+startPos)
				length = @filePiece.pieceLength - startPos
			end
			if ((@filePiece.segment_number * @filePiece.pieceLength+startPos+length) > @filePiece.fileSize)
				length = @filePiece.fileSize-(@filePiece.segment_number * @filePiece.pieceLength+startPos) 
			end	
			
			if (length > @requestSize)
				length = @requestSize
			end

			sentMessage = "[#{to_s}]: Sent Request #{@filePiece.segment_number}:#{@filePiece.position}->#{@filePiece.position+length}"
			msg = [13,6, @filePiece.segment_number, startPos, length].pack('NCNNN')
			queuePacket(msg,sentMessage)
		end
	end
	
	def keepAlive()
		begin
			sentMessage = "[#{to_s}]: Sent Keep Alive"
			queuePacket("\000", sentMessage)
		rescue Exception => e
			puts debugMessage("[#{to_s}]: Keep Alive Error: #{e}")
		end
	end

			
	def readFromSocket(amount)
		messagePrefixRaw = ""
		#messagePrefixRaw = @socket.readpartial(amount) 
		amountReceived = 0
		timeout(20) do
			begin
				while amountReceived < amount
					recv = @socket.readpartial(amount-amountReceived) 
					amountReceived+= recv.length
					messagePrefixRaw+=recv
				end
				#while chunk = f.sysread(amount) 
				#	messagePrefixRaw+=chunk.length
				#end
			rescue EOFError 
				puts debugMessage("[#{to_s}]: Error Reading #{amount} bytes.  Socket closed")
				return nil
			rescue Exception=>e
				#warn "Holy shit! #{e}" 
				puts debugMessage("[#{to_s}]: Error Reading #{amount} bytes.  Bad data")
				#messagePrefixRaw = @socket.read(amount)
				#puts "#{messagePrefixRaw.inspect}"
				return nil
			end
		end	
		return messagePrefixRaw
	end
	
	def requestPiece()
		length = @requestSize
		msg = [13,6, @filePiece.segment_number, 0, length].pack('NCNNN')
		sentMessage = "[#{to_s}]: Sent Request #{@filePiece.segment_number}:#{@filePiece.position}->#{@filePiece.position+length}"
		queuePacket(msg,sentMessage)
	end
	
	def sendInterested()
		am_interested = true
		begin
			sentMessage = "[#{to_s}]: Sent Interested"
			queuePacket([1,2].pack('NC'),sentMessage)
			@interestedRequestTime = Time.now
		rescue StandardError=>e 
			puts debugMessage("[#{to_s}]: Send Interested Error: #{e}")
			valid = false
		end
	end

	def sendNotInterested(sent = "Sent Not Interested")
		am_interested = true
		begin
			sentMessage = "[#{to_s}]: #{sent}"
			queuePacket([1,3].pack('NC'),sentMessage)
			@interestedRequestTime = Time.now
			sentMessage = "[#{to_s}]: Sent Not Interested"
		rescue StandardError=>e 
			puts debugMessage("[#{to_s}]: Send Not Interested Error: #{e}")
			valid = false
		end
	end
	
	
	def sendUnchoke()
		am_choking = false
		begin
			sentMessage ="[#{to_s}]: Sent Unchoke"
			queuePacket([1,1].pack('NC'),sentMessage)
		rescue StandardError=>e 
			puts debugMessage("[#{to_s}]: Send Unchoke Error: #{e}")
			valid = false
		end
	end
	
	def sendChoke()
		am_choking = false
		begin
			sentMessage = "[#{to_s}]: Sent Choke"
			queuePacket([1,0].pack('NC'),sentMessage)
		rescue StandardError=>e 
			puts debugMessage("[#{to_s}]: Send Choke Error: #{e}")
			valid = false
		end
	end
	
	def sendPiece(dataBlock, indexPoint, beginPoint)
		begin
			length = 1+4+4+dataBlock.length
			packet =[length,7,indexPoint.to_s.to_i,beginPoint.to_s.to_i].pack('NCNN')
			packet+=dataBlock
			sentMessage = "[#{to_s}]: Sent Piece #{indexPoint}:#{beginPoint}->#{beginPoint.to_s.to_i+dataBlock.length.to_i}"
			queuePacket(packet,sentMessage)
		rescue StandardError=>e 
			puts debugMessage("[#{to_s}]: Send Piece Error: #{e}")
			valid = false
		end
	end

	def addPiece(piece)
		@has[piece.segment_number] = piece
		allComplete = true
		
		@completeCount = 0.0
		count = 0
		@has.each{|pieceNumber|
			if pieceNumber == false
				allComplete = false
			else 
				count +=1.0
			end
		}
	
		totalPieces = @has.length.to_i
		completedPiecesCount = count
		
		@completeCount = completedPiecesCount/totalPieces	
		@isSeeding = allComplete
	end
	
	# Initiate a handshake with the peer
	def handshake(initiator)
		if @socket == nil && (initiator!=true || initiator!=false)
			@valid = false
			return
		end

		begin
			if initiator==true
				sendHandshake()
				readHandshake()
			else
				readHandshake()
				sendHandshake()
			end
			
			@running = true
		rescue Exception => e
			@valid = false 
			puts debugMessage("[#{to_s}]: Error #{initiator ? "Initiating": "Receiving"} Handshake:   #{e}")
		end
		
		# send the bitfield
		if @running == true && @valid == true
			puts debugMessage("[#{to_s}]: Handshake Successful")
			sendBitfield(@bitfield)
		end
	end
		
	def validateID(id)
		validNewID = true
		validOldID = true
		# check the new id
		if id == nil || id == "" || id == "                    " # it never updated from the default value.  something went wrong
			validNewID = false
		end
		# check the old id
		if @id == nil || @id == "" ||  @id == "                    " # it never updated from the default value.  something went wrong
			validOldID = false
		end
		
		#compare the two
		if validNewID && !validOldID # passing in a new ID, the replacing the old one
			@id = id
		elsif (validNewID && validOldID) || (validOldID && !validNewID)
			if @id != id # the two id's dont match up.  slight problem
				puts debugMessage("[#{to_s}]: Handshake Peer ID does not match torrents. Using handshake ID")
				@id = id
			end
		else
			@id = ""
			puts debugMessage("[#{to_s}]: Invalid Peer ID")
			valid = false
		end
	end
	
	def readHandshake()
		cLen = readFromSocket(1)[0]
		cName = readFromSocket(19)
		cReserved = readFromSocket(8)
		cHash = readFromSocket(20)
		id = readFromSocket(20)
		 
		validateID(id)
		
		if cHash != @completeHash
			#@valid = false
		end
	end
	
	def sendHandshake()
		@socket.send("\023BitTorrent protocol\0\0\0\0\0\0\0\0",0)
		@socket.send("#{@completeHash}#{@clientID}",0)	
	end

	def sendBitfield(bitfield)
		begin
			messageLen = bitfield.length + 1 
			messageLen = [bitfield.join].pack('B*').length+1
			sentMessage = "[#{to_s}]: Sent Bitfield"
			queuePacket([messageLen,5,bitfield.join.to_s].pack('NCB*'),sentMessage)
		rescue Exception => e
			puts debugMessage("[#{to_s}]: Error Sending Bitfield: #{e}")
		end
	end
	
	def getBlocks()
		output =  "|"
		@has.each{ |x|
			if x
				output+= "Y"
			else
				output+= "N"
			end
		}
		output+= "|"		
		return output
	end
	
	# Selects a rarest piece.  upon a tie will randomly select among the group
	def getRarestPiece(rarityList)
		rarestFrequency = 999999999
		rarestIdleList = []
		
		rarityList.each_pair{|x,y|
			if (x.status == "idle" || x.status == "downloading") && y > 0 && y < rarestFrequency
				rarestFrequency = y
			end
		}
		
		if rarestFrequency == 999999999
		
			return nil
		end
		
		rarityList.each{ |x,y|
			if y == rarestFrequency 
				rarestIdleList.push(x)
			end
		}
		rarestIdleList.sort_by{rand}.each{ |piece|
			
			if @has[piece.segment_number] && piece.status == "idle"
				piece.status = "downloading"
				return piece
			end
		}
		return nil
	end

	def sendHave(pieceNo)
		begin
			length = 5
			id = 4
			packet = [length,id,pieceNo.to_i].pack('NCN')
			sentMessage = "[#{to_s}]: Sent Have #{pieceNo}"
			queuePacket(packet,sentMessage)
		rescue StandardError=>e
			puts debugMessage("[#{to_s}]: Have Piece Error: #{e}")
		end
	end

	def to_s()		
		if @id ==nil || @ip == nil || @port == nil
			return ""
		end
		 
		ipPortFormat = "#{@ip}:#{@port}]".to_s.ljust(21, ' ')
		
		if @id == "                    " || @id == nil || @id == ""
			idFormat = ""
		else 
			total = @completeCount*100
			completePercent = ("%03.1f" % total)
			#idFormat = "[#{@id}(#{"%05.1f" % total})".to_s.ljust(26, ' ')
			idFormat = "[#{@id}(#{completePercent})".to_s.ljust(26, ' ')
		end

		return "#{ipPortFormat} #{idFormat}"
	end
	
	def debugMessage(message)
		time = Time.now;
		return "[#{time.strftime("%X")}] #{message}"
	end
end
