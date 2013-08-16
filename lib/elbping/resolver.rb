
require 'resolv'

class TcpDNS < Resolv::DNS
  # This is largely a copy-paste job from mri/source/lib/resolv.rb
  def fetch_resource(name, typeclass)
    lazy_initialize
    request = make_tcp_requester
    sends = {}
    begin
      @config.resolv(name) { |candidate, tout, nameserver, port|
        msg = Message.new
        msg.rd = 1
        msg.add_question(candidate, typeclass)
        unless sender = senders[[candidate, nameserver, port]]
          sender = senders[[candidate, nameserver, port]] =
            requester.sender(msg, candidate, nameserver, port)
        end
        reply, reply_name = requester.request(sender, tout)
        case reply.rcode
        when RCode::NoError
          if reply.tc == 1 and not Requester::TCP === requester
            requester.close
            # Retry via TCP:
            requester = make_tcp_requester(nameserver, port)
            senders = {}
            # This will use TCP for all remaining candidates (assuming the
            # current candidate does not already respond successfully via
            # TCP).  This makes sense because we already know the full
            # response will not fit in an untruncated UDP packet.
            redo
          else
            yield(reply, reply_name)
          end
          return
        when RCode::NXDomain
          raise Config::NXDomain.new(reply_name.to_s)
        else
          raise Config::OtherResolvError.new(reply_name.to_s)
        end
      }
    ensure
      requester.close
    end
  end
end

module ElbPing
  module Resolver
    def self.resolve_ns(nameserver)
      # Leftover from a resolver lib that wouldn't resolve its own nameservers
      return [nameserver]
    end

    # Resolve an ELB address to a list of node IPs. Should always return a list
    # as long as the server responded, even if it's empty.
    def self.find_elb_nodes(target, nameserver, timeout=5)
      # `timeout` is in seconds
      ns_addrs = resolve_ns nameserver

      # Now resolve our ELB nodes
      resp = nil
      Timeout::timeout(timeout) do 
        TcpDNS.open :nameserver => ns_addrs, :search => '', :ndots => 1 do |dns|
          # TODO: Exceptions
          resp = dns.getresources target, Resolv::DNS::Resource::IN::A
        end
      end
      resp.map { |r| r.address.to_s }
    end
  end
end

