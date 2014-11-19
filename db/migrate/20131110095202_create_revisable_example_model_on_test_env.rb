class CreateRevisableExampleModelOnTestEnv < ActiveRecord::Migration
  def change
    if Rails.env.test? || ENV['RAILS_ENV'] == :test
      create_table :revisable_example_models do |t|
        t.string :example_value
        t.timestamps
      end
    end
  end
end
