# Every survey connection test answers a check it does not know the same way,
# so each of them says so with one line instead of its own example.
RSpec.shared_examples 'a survey connection test' do
  it 'reports an error for an unknown check' do
    expect(tester.call(check: 'bogus', values: {})).to have_attributes(ok: false, reason: :error)
  end
end
