class Packet
	attr_accessor :message, :peer, :timeToSend
	def initalize(message,socket,timeToSend)
		@message = message
		@peer = peer
		@timeToSend = timeToSend
	end
end

class Schedule
	@@events = Array.new
	def Schedule.delay()
		if @@events.empty? then
			nil
		else
			[ @@events[0][0] - Time.now, 0 ].max
		end
	end
	def Schedule.at(time, &block)
		@@events.push( [ time, block ] )
		@@events.sort! { |a,b| a[0] <=> b[0] }
	end

end

class PacketQueue
	attr_accessor :waitingEvent
	@_queue = Array.new

	def initialize()
		@_queue = []
		@_lastSentTime = Time.now
	end

	def RunPending()
		while ( !@_queue.empty? and
			@_events[0][0] <= Time.now ) do
			time, block = @@events.shift
			puts "Time:#{Time.now-@@startTime}"
			block.call
			
		end
	end
	
	def Enqueue(peer, message)
		@_queue.push( [time,peer,message] )
		@_queue.sort! { |a,b| a[0] <=> b[0] }
		
		packet.message = message
		packet.
		
		
		wait.timeToSend = Time.now+(waitingMessages*0.1)
		wait.message = message
		wait.neighbor = neighbor
		@_queue.push(wait)
	
	
	
	
	end
		neighbor = @@table.findRecordBySource(destination_address)
		if neighbor == nil || !neighbor.isAlive()
			puts "ERROR:NOROUTE"
			return
		else
			waitingMessages = queuedMessages(neighbor) #number in the queue
			
			if waitingMessages > 10 #too many messages.  drop the packet
				puts "ERROR:NOBUFF" 						
			else
				wait = WaitingMessage.new
				wait.timeToSend = Time.now+(waitingMessages*0.1)
				wait.message = message
				wait.neighbor = neighbor
				@_queue.push(wait)
			end
		end
		sort()
	end
	
	def retimePackets(neighbor)
		
		count = 1
		@_queue.each{|x|
			if x.neighbor == neighbor
				x.timeToSend = Time.now+(0.1*count)
				count+=1
			end
		}
		printQueue()		
	end	
	
	def sort()
		@_queue = @_queue.sort do |a,b|  
			a.timeToSend <=> b.timeToSend   # Sort by second entry  
		end
		@waitingEvent = @_queue.first
	end
	
	def Dequeue()
		if @_queue.empty? then return nil
		else 
			deleted_element = @_queue.delete_at(0)
			sort()
			return deleted_element
		end
	end
	
	def queuedMessages(neighbor)
		neighborCount = 0;
		@_queue.each{|x|
			if x.neighbor == neighbor
				neighborCount=neighborCount+1 
			end
		}
		return neighborCount
	end
	
	def printQueue()
		puts "Sending in\t\tAddress\t\tSend In"
		@_queue.each{|x| 
			puts "#{x.timeToSend-Time.now}\t\t#{x.message}\t\t#{x.neighbor.source_address}" if x.neighbor!="all"
		}
	end
end