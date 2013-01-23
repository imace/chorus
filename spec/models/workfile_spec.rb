require 'spec_helper'

describe Workfile do
  describe "validations" do
    it { should validate_presence_of :file_name }

    context "normalize the file name" do
      let!(:another_workfile) { FactoryGirl.create(:workfile, :file_name => 'workfile.sql') }

      context "first conflict" do
        it "renames and turns the workfile valid" do
          workfile = Workfile.new(:file_name => "workfile.sql")
          workfile.workspace = another_workfile.workspace
          workfile.owner = another_workfile.owner

          workfile.should be_valid
          workfile.file_name.should == 'workfile_1.sql'
        end
      end

      context "multiple conflicts" do
        let(:workspace) { FactoryGirl.create(:workspace) }
        let!(:another_workfile_1) { FactoryGirl.create(:workfile, :workspace => workspace, :file_name => 'workfile.sql') }
        let!(:another_workfile_2) { FactoryGirl.create(:workfile, :workspace => workspace, :file_name => 'workfile.sql') }

        it "increases the name suffix number" do
          workfile = Workfile.new :file_name => 'workfile.sql'
          workfile.workspace = workspace
          workfile.owner = another_workfile_1.owner

          workfile.save
          workfile.should be_valid
          workfile.file_name.should == 'workfile_2.sql'
        end
      end
    end
  end

  describe ".validate_name_uniqueness" do
    let!(:workspace) { FactoryGirl.create(:workspace) }
    let!(:other_workspace) { FactoryGirl.create(:workspace) }
    let!(:existing_workfile) { FactoryGirl.create(:workfile, :workspace => workspace, :file_name => 'workfile.sql') }

    it "returns false and adds an error to the error list if name in workspace is taken" do
      new_workfile = Workfile.new :file_name => 'workfile.sql'
      new_workfile.workspace = workspace
      new_workfile.validate_name_uniqueness.should be_false
      new_workfile.should have_error_on(:file_name)
    end

    it "returns true if there are no conflicts in its own workspace" do
      new_workfile = Workfile.new :file_name => 'workfile.sql'
      new_workfile.workspace = other_workspace
      new_workfile.validate_name_uniqueness.should be_true
      new_workfile.should be_valid
    end
  end

  describe "associations" do
    it { should belong_to :owner }
    it { should have_many :activities }
    it { should have_many :events }
    it { should have_many :notes }
    it { should have_many :comments }

    describe "#notes" do
      let(:workfile) { workfiles(:private) }
      let(:author) { workfile.owner }

      it "should return notes" do
        note = Events::NoteOnWorkfile.by(author).add(:workfile => workfile, :body => "note on a workfile", :workspace => workfile.workspace)
        workfile.reload
        workfile.notes.first.should be_a(Events::NoteOnWorkfile)
        workfile.notes.should == [note]
      end
    end
  end

  describe "search fields" do
    it "indexes text fields" do
      Workfile.should have_searchable_field :file_name
      Workfile.should have_searchable_field :description
    end
  end

  describe "entity_type" do
    it "should return 'workfile'" do
      Workfile.new.entity_type.should == 'workfile'
    end
  end

  describe "copy" do
    let(:workfile) { workfiles(:public) }
    let(:workspace) { workspaces(:private) }
    let(:user) { users(:admin) }

    it "copies the associated data" do
      new_workfile = workfile.copy(user, workspace)
      new_workfile.file_name = workfile.file_name
      new_workfile.description = workfile.description
      new_workfile.workspace = workspace
      new_workfile.owner = user
    end

    it "copies any additional_data" do
      workfile.additional_data["something"] = "here"
      new_workfile = workfile.copy(user, workspace)
      new_workfile.additional_data["something"].should == "here"
    end
  end
end
