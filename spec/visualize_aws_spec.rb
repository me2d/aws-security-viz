require 'spec_helper'

describe VisualizeAws do
  before do
    @ec2 = double(Fog::Compute)
    allow(Fog::Compute).to receive(:new).and_return(@ec2)
  end

  let(:visualize_aws) { VisualizeAws.new(AwsConfig.new) }

  it 'should add nodes, edges for each security group' do
    expect(@ec2).to receive(:security_groups).and_return([group('Remote ssh', group_ingress('22', 'My machine')), group('My machine')])
    graph = visualize_aws.build

    expect(graph.ops).to eq([
                [:node, 'Remote ssh'],
                [:edge, 'My machine', 'Remote ssh', {:color => :blue, :label => '22/tcp'}],
                [:node, 'My machine'],
            ])
  end

  context 'groups' do
    it 'should add nodes for external security groups defined through ingress' do
      expect(@ec2).to receive(:security_groups).and_return([group('Web', group_ingress('80', 'ELB'))])
      graph = visualize_aws.build

      expect(graph.ops).to eq([
                  [:node, 'Web'],
                  [:edge, 'ELB', 'Web', {:color => :blue, :label => '80/tcp'}],
              ])
    end

    it 'should add an edge for each security ingress' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('App', group_ingress('80', 'Web'), group_ingress('8983', 'Internal')),
                  group('Web', group_ingress('80', 'External')),
                  group('Db', group_ingress('7474', 'App'))
              ])
      graph = visualize_aws.build

      expect(graph.ops).to eq([
                  [:node, 'App'],
                  [:edge, 'Web', 'App', {:color => :blue, :label => '80/tcp'}],
                  [:edge, 'Internal', 'App', {:color => :blue, :label => '8983/tcp'}],
                  [:node, 'Web'],
                  [:edge, 'External', 'Web', {:color => :blue, :label => '80/tcp'}],
                  [:node, 'Db'],
                  [:edge, 'App', 'Db', {:color => :blue, :label => '7474/tcp'}],
              ])

    end
  end

  context 'cidr' do

    it 'should add an edge for each cidr ingress' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('Web', group_ingress('80', 'External')),
                  group('Db', group_ingress('7474', 'App'), cidr_ingress('22', '127.0.0.1/32'))
              ])
      graph = visualize_aws.build

      expect(graph.ops).to eq([
                  [:node, 'Web'],
                  [:edge, 'External', 'Web', {:color => :blue, :label => '80/tcp'}],
                  [:node, 'Db'],
                  [:edge, 'App', 'Db', {:color => :blue, :label => '7474/tcp'}],
                  [:edge, '127.0.0.1/32', 'Db', {:color => :blue, :label => '22/tcp'}],
              ])

    end

    it 'should add map edges for cidr ingress' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('Web', group_ingress('80', 'External')),
                  group('Db', group_ingress('7474', 'App'), cidr_ingress('22', '127.0.0.1/32'))
              ])
      mapping = {'127.0.0.1/32' => 'Work'}
      mapping = CidrGroupMapping.new([], mapping)
      allow(CidrGroupMapping).to receive(:new).and_return(mapping)

      graph = visualize_aws.build

      expect(graph.ops).to eq([
                  [:node, 'Web'],
                  [:edge, 'External', 'Web', {:color => :blue, :label => '80/tcp'}],
                  [:node, 'Db'],
                  [:edge, 'App', 'Db', {:color => :blue, :label => '7474/tcp'}],
                  [:edge, 'Work', 'Db', {:color => :blue, :label => '22/tcp'}],
              ])

    end

    it 'should group mapped duplicate edges for cidr ingress' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('ssh', cidr_ingress('22', '192.168.0.1/32'), cidr_ingress('22', '127.0.0.1/32'))
              ])
      mapping = {'127.0.0.1/32' => 'Work', '192.168.0.1/32' => 'Work'}
      mapping = CidrGroupMapping.new([], mapping)
      allow(CidrGroupMapping).to receive(:new).and_return(mapping)

      graph = visualize_aws.build

      expect(graph.ops).to eq([
                  [:node, 'ssh'],
                  [:edge, 'Work', 'ssh', {:color => :blue, :label => '22/tcp'}],
              ])
    end
  end

  context "filter" do
    it 'include cidr which do not match the pattern' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('Web', cidr_ingress('22', '127.0.0.1/32')),
                  group('Db', cidr_ingress('22', '192.0.1.1/32'))
              ])

      opts = {:exclude => ['127.*']}
      graph = VisualizeAws.new(AwsConfig.new(opts)).build

      expect(graph.ops).to eq([
                  [:node, 'Web'],
                  [:node, 'Db'],
                  [:edge, '192.0.1.1/32', 'Db', {:color => :blue, :label => '22/tcp'}],
              ])
    end

    it 'include groups which do not match the pattern' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('Web', group_ingress('80', 'External')),
                  group('Db', group_ingress('7474', 'App'), cidr_ingress('22', '127.0.0.1/32'))
              ])

      opts = {:exclude => ['D.*b', 'App']}
      graph = VisualizeAws.new(AwsConfig.new(opts)).build

      expect(graph.ops).to eq([
                  [:node, 'Web'],
                  [:edge, 'External', 'Web', {:color => :blue, :label => '80/tcp'}],
              ])
    end

    it 'include derived groups which do not match the pattern' do
      expect(@ec2).to receive(:security_groups).and_return(
              [
                  group('Web', group_ingress('80', 'External')),
                  group('Db', group_ingress('7474', 'App'), cidr_ingress('22', '127.0.0.1/32'))
              ])

      opts = {:exclude => ['App']}
      graph = VisualizeAws.new(AwsConfig.new(opts)).build

      expect(graph.ops).to eq([
                  [:node, 'Web'],
                  [:edge, 'External', 'Web', {:color => :blue, :label => '80/tcp'}],
                  [:node, 'Db'],
                  [:edge, '127.0.0.1/32', 'Db', {:color => :blue, :label => '22/tcp'}],
              ])

    end
  end
end
