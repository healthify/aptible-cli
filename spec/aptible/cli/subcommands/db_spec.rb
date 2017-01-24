require 'spec_helper'

class SocatHelperMock < OpenStruct
end

describe Aptible::CLI::Agent do
  before { subject.stub(:ask) }
  before { subject.stub(:save_token) }
  before { subject.stub(:fetch_token) { double 'token' } }

  let(:handle) { 'foobar' }
  let(:database) { Fabricate(:database, handle: handle) }
  let(:socat_helper) { SocatHelperMock.new(port: 4242) }

  describe '#db:tunnel' do
    it 'should fail if database is non-existent' do
      allow(Aptible::Api::Database).to receive(:all) { [] }
      expect do
        subject.send('db:tunnel', handle)
      end.to raise_error("Could not find database #{handle}")
    end

    context 'valid database' do
      before { allow(Aptible::Api::Database).to receive(:all) { [database] } }

      it 'prints a message explaining how to connect' do
        cred = Fabricate(:database_credential, default: true, type: 'foo',
                                               database: database)

        expect(subject).to receive(:with_local_tunnel).with(cred, 0)
          .and_yield(socat_helper)

        expect(subject).to receive(:say)
          .with('Creating foo tunnel to foobar...', :green)

        local_url = 'postgresql://aptible:password@localhost.aptible.in:4242/db'
        expect(subject).to receive(:say)
          .with("Connect at #{local_url}", :green)

        # db:tunnel should also explain each component of the URL and suggest
        # the --type argument:
        expect(subject).to receive(:say).exactly(9).times
        subject.send('db:tunnel', handle)
      end

      it 'defaults to a default credential' do
        ok = Fabricate(:database_credential, default: true, database: database)
        Fabricate(:database_credential, database: database, type: 'foo')
        Fabricate(:database_credential, database: database, type: 'bar')

        messages = []
        allow(subject).to receive(:say) { |m, *| messages << m }
        expect(subject).to receive(:with_local_tunnel).with(ok, 0)

        subject.send('db:tunnel', handle)

        expect(messages.grep(/use --type type/im)).not_to be_empty
        expect(messages.grep(/valid types.*foo.*bar/im)).not_to be_empty
      end

      it 'supports --type' do
        subject.options = { type: 'foo' }

        Fabricate(:database_credential, default: true, database: database)
        ok = Fabricate(:database_credential, type: 'foo', database: database)
        Fabricate(:database_credential, type: 'bar', database: database)

        allow(subject).to receive(:say)
        expect(subject).to receive(:with_local_tunnel).with(ok, 0)
        subject.send('db:tunnel', handle)
      end

      it 'fails when there is no default database credential nor type' do
        Fabricate(:database_credential, default: false, database: database)

        expect { subject.send('db:tunnel', handle) }
          .to raise_error(/no default credential/im)
      end

      it 'fails when the type is incorrect' do
        subject.options = { type: 'bar' }

        Fabricate(:database_credential, type: 'foo', database: database)

        expect { subject.send('db:tunnel', handle) }
          .to raise_error(/no credential with type bar/im)
      end

      it 'fails when the database is not provisioned' do
        database.stub(status: 'pending')

        expect { subject.send('db:tunnel', handle) }
          .to raise_error(/foobar is not provisioned/im)
      end
    end
  end

  describe '#db:list' do
    before do
      staging = Fabricate(:account, handle: 'staging')
      prod = Fabricate(:account, handle: 'production')

      [[staging, 'staging-redis-db'], [staging, 'staging-postgres-db'],
       [prod, 'prod-elsearch-db'], [prod, 'prod-postgres-db']].each do |a, h|
        Fabricate(:database, account: a, handle: h)
      end

      token = 'the-token'
      allow(subject).to receive(:fetch_token).and_return(token)
      allow(Aptible::Api::Account).to receive(:all).with(token: token)
        .and_return([staging, prod])
    end

    context 'when no account is specified' do
      it 'prints out the grouped database handles for all accounts' do
        allow(subject).to receive(:say)

        subject.send('db:list')

        expect(subject).to have_received(:say).with('=== staging')
        expect(subject).to have_received(:say).with('staging-redis-db')
        expect(subject).to have_received(:say).with('staging-postgres-db')

        expect(subject).to have_received(:say).with('=== production')
        expect(subject).to have_received(:say).with('prod-elsearch-db')
        expect(subject).to have_received(:say).with('prod-postgres-db')
      end
    end

    context 'when a valid account is specified' do
      it 'prints out the database handles for the account' do
        allow(subject).to receive(:say)

        subject.options = { environment: 'staging' }
        subject.send('db:list')

        expect(subject).to have_received(:say).with('=== staging')
        expect(subject).to have_received(:say).with('staging-redis-db')
        expect(subject).to have_received(:say).with('staging-postgres-db')

        expect(subject).to_not have_received(:say).with('=== production')
        expect(subject).to_not have_received(:say).with('prod-elsearch-db')
        expect(subject).to_not have_received(:say).with('prod-postgres-db')
      end
    end

    context 'when an invalid account is specified' do
      it 'prints out an error' do
        allow(subject).to receive(:say)

        subject.options = { environment: 'foo' }
        expect { subject.send('db:list') }.to raise_error(
          'Specified account does not exist'
        )
      end
    end
  end

  describe '#db:backup' do
    before { allow(Aptible::Api::Account).to receive(:all) { [account] } }
    before { allow(Aptible::Api::Database).to receive(:all) { [database] } }

    let(:op) { Fabricate(:operation) }

    it 'allows creating a new backup' do
      expect(database).to receive(:create_operation!).and_return(op)
      expect(subject).to receive(:say).with('Backing up foobar...')
      expect(subject).to receive(:attach_to_operation_logs).with(op)

      subject.send('db:backup', handle)
    end

    it 'fails if the DB is not found' do
      expect { subject.send('db:backup', 'nope') }
        .to raise_error(Thor::Error, 'Could not find database nope')
    end
  end
end
