require 'spec_helper'

describe OracleViewAccess do
  let(:context) { Object.new }
  let(:access) { JdbcViewAccess.new(context)}
  let(:view) { datasets(:jdbc_view) }

  before do
    stub(context).current_user { user }
  end

  describe '#show?' do
    context 'if the user is an admin' do
      let(:user) { users(:admin) }

      it 'allows access' do
        access.can?(:show, view).should be_true
      end
    end

    context "if the user has access to the view's data source" do
      let(:user) { users(:the_collaborator) }

      it 'allows access' do
        access.can?(:show, view).should be_true
      end
    end

    context "if the user does not have access to the view's data source" do
      let(:user) { users(:the_collaborator) }

      before do
        any_instance_of(JdbcDataSourceAccess) do |instance|
          stub(instance).can? :show, view.data_source { false }
        end
      end

      it 'prevents access' do
        access.can?(:show, view).should be_false
      end
    end
  end
end
