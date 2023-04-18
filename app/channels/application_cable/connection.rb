module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :judge_server, :current_user, :single_contest
    
    def initialize(*args)
      super
      @mutex = Mutex.new
    end

    def connect
      if request.params['key']
        @mutex.synchronize do
          return if @disconnected
          judge_server = find_judge_server
          judge_server.with_lock do
            reject_unauthorized_connection if judge_server.online
            judge_server.update(online: true)
          end
          self.judge_server = judge_server
        end
      else
        self.single_contest = find_single_contest
        self.current_user = find_user
      end
    end

    def disconnect
      # connect and disconnect may be called in different thread simutaneously, thus use a mutex to prevent races
      @mutex.synchronize do
        if self.judge_server
          begin
            self.judge_server.update(online: false)
          rescue ActiveRecord::StatementInvalid => e
            # This happens once in a while when the server restarts;
            #  disconnect the connection pool to prevent the server being stuck by ~1min because of stale connections
            ActiveRecord::Base.connection_pool.disconnect
          end
        end
        @disconnected = true
      end
    end

    private

    def find_judge_server
      key = request.params['key']
      version = request.params['version']
      reject_unauthorized_connection if not key or not version
      reject_unauthorized_connection if not Gem::Version.new(version).between?(Gem::Version.new('1.3.0') , Gem::Version.new('2'))
      judge = JudgeServer.find_by(key: key)
      reject_unauthorized_connection if not judge or (not (judge.ip || "").empty? and judge.ip != request.remote_ip)
      judge
    end

    def find_user
      user_id = request.session&.dig('warden.user.user.key', 0, 0)
      return nil unless user_id
      user = User.find_by(id: user_id)
      reject_unauthorized_connection unless user
      user
    end

    def find_single_contest
      contest_id = request.headers['HTTP_SINGLE_CONTEST_ID']
      return nil unless contest_id
      contest = Contest.find_by(id: contest_id.to_i)
      reject_unauthorized_connection unless contest
      contest
    end
  end
end
