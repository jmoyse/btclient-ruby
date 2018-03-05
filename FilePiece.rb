require 'digest/sha1'
class FilePiece
	attr_accessor :segment_number, :status, :pieceLength, :complete, :position, :fileSize

	def initialize(segment_number,pieceHash,pieceLength,fileSize, filename)
		@position = 0
		@segment_number = segment_number
		@pieceHash = pieceHash
		@pieceLength = pieceLength
		@status = "idle" # supported status: downloading, idle
		@complete = false
		@fileSize = fileSize
		@filename = filename
		@requestSize = 16384
		@blocks = Array.new(@pieceLength/@requestSize)
	end
	
	def append(data,indexPoint,beginPoint)
		if data.length == 0 || @complete || @position>=@pieceLength
			puts "can't append, zomg"
			return
		end
		
		#fix the variables on this puts "Appending #{payload.length} bytes onto piece #{peer.filePiece.segment_number}(#{indexPointoint.to_s}) at (#{beginPointoint.to_s},#{beginPointoint.to_s.to_i+p.length})"
		absoute_pos = indexPoint.to_s.to_i*@pieceLength+beginPoint.to_s.to_i
		f = File.new(@filename,  "r+b")
		f.seek(absoute_pos, IO::SEEK_SET)
		f.print(data)
		f.close
				
		@position+=data.length

		if @position >= @pieceLength || ((indexPoint.to_s.to_i*@pieceLength)+position)>= @fileSize
			if checkHash()
				debugMessage("Piece #{@segment_number} checksum verified")
				
				#uts "Piece #{@segment_number} (#{pieceLength}B) completed and passed SHA1 checksum" #written to disk at #{(indexPoint.to_s.to_i*@pieceLength)+beginPoint.to_s.to_i}"
			else
				@complete = false
				@status = "idle"
				@position = 0
				puts "failed checksum"
			end
		end
	end

	def getBlock(startPos,length)
		bytes = ""
		f = File.new(@filename,  "r+b")
		f.seek(@segment_number * @pieceLength+startPos, IO::SEEK_SET)
		bytes = f.read(length)
		if bytes.length > 0 
			return bytes
		end
		return nil
	end
	
	def size()
		block = @segment_number*@pieceLength
		if (block+@pieceLength) > @fileSize # we're on the last block
			return @fileSize-block
		end
		return @pieceLength
	end
	
	def checkHash()
		bytes = ""
		f = File.new(@filename,  "r+b")
		f.seek(@segment_number * @pieceLength, IO::SEEK_SET)

		seekTo = @pieceLength
		if f.pos+@pieceLength > @fileSize # last block
			seekTo = @fileSize-f.pos
		end
		
		bytes = f.read(seekTo)
		h = ""
		if bytes
			h = Digest::SHA1.digest(bytes)
		end
		
		f.close
		
		if @pieceHash == h
			@complete = true
			@status = "complete"
			return true
		end
		return false
	end
	
	def to_s
		return "piece ##{segment_number}"
	end
	
	# TODO: Write the zero out block
	def zeroOutBlock()
		f = File.new(@filename,  "r+b")
		f.seek(@segment_number * @pieceLength, IO::SEEK_SET)
		zeroBlock = ""
		@pieceLength.times{
			zeroBlock+="0"
		}
		 
		bytes = f.print(zeroBlock)
		if bytes
			h = Digest::SHA1.digest(bytes)
		end
	end
	
	def eql?(o)
		o.is_a?(FilePiece) && pieceHash == o.pieceHash
	end

	def hash
		@segment_number
	end
	
	def debugMessage(message)
		time = Time.now;
		return "[#{time.strftime("%X")}] #{message}"
	end
	
end
