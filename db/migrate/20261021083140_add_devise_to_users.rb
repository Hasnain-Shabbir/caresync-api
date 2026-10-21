class AddDeviseToUsers < ActiveRecord::Migration[8.1]
  def change
    rename_column :users, :password_digest, :encrypted_password

    # recoverable
    add_column :users, :reset_password_token, :string
    add_column :users, :reset_password_sent_at, :datetime
    add_index  :users, :reset_password_token, unique: true

    # lockable
    add_column :users, :failed_attempts, :integer, default: 0, null: false
    add_column :users, :unlock_token, :string
    add_column :users, :locked_at, :datetime
    add_index  :users, :unlock_token, unique: true
  end
end
