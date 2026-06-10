const { extractCredentials } = require('../../playwright/providers/aws');

function makeMockPage(inputs) {
  return {
    waitForSelector: jest.fn().mockResolvedValue(undefined),
    locator: jest.fn().mockReturnValue({
      all: jest.fn().mockResolvedValue(
        inputs.map(inp => ({
          inputValue: jest.fn().mockResolvedValue(inp.value),
          evaluateHandle: jest.fn().mockResolvedValue({
            evaluate: jest.fn().mockResolvedValue(inp.label),
          }),
        }))
      ),
    }),
  };
}

describe('aws provider extraction', () => {
  let outputFn;

  beforeEach(() => {
    outputFn = jest.fn();
  });

  test('label-matched extraction emits all credentials', async () => {
    const page = makeMockPage([
      { label: 'Access Key ID', value: 'AKIA123' },
      { label: 'Secret Access Key', value: 'secret123' },
      { label: 'Session Token', value: 'token123' },
    ]);

    await extractCredentials(page, outputFn);

    expect(outputFn).toHaveBeenCalledTimes(1);
    expect(outputFn).toHaveBeenCalledWith({
      AWS_ACCESS_KEY_ID: 'AKIA123',
      AWS_SECRET_ACCESS_KEY: 'secret123',
      AWS_SESSION_TOKEN: 'token123',
    });
  });

  test('positional fallback uses the third, fourth, and fifth inputs', async () => {
    const page = makeMockPage([
      { label: '', value: 'first' },
      { label: '', value: 'second' },
      { label: '', value: 'AKIA456' },
      { label: '', value: 'secret456' },
      { label: '', value: 'token456' },
    ]);

    await extractCredentials(page, outputFn);

    expect(outputFn).toHaveBeenCalledWith({
      AWS_ACCESS_KEY_ID: 'AKIA456',
      AWS_SECRET_ACCESS_KEY: 'secret456',
      AWS_SESSION_TOKEN: 'token456',
    });
  });

  test('missing access key throws', async () => {
    const page = makeMockPage([
      { label: '', value: 'secret-only' },
    ]);

    await expect(extractCredentials(page, outputFn)).rejects.toThrow(
      'Could not find AWS Access Key and Secret Key'
    );
  });

  test('no session token omits the token field', async () => {
    const page = makeMockPage([
      { label: 'Access Key ID', value: 'AKIA789' },
      { label: 'Secret Access Key', value: 'secret789' },
    ]);

    await extractCredentials(page, outputFn);

    expect(outputFn).toHaveBeenCalledWith({
      AWS_ACCESS_KEY_ID: 'AKIA789',
      AWS_SECRET_ACCESS_KEY: 'secret789',
    });
  });

  test('outputFn called with correct keys', async () => {
    const page = makeMockPage([
      { label: 'Access Key ID', value: 'AKIA999' },
      { label: 'Secret Access Key', value: 'secret999' },
    ]);

    await extractCredentials(page, outputFn);

    expect(outputFn).toHaveBeenCalledTimes(1);
    expect(outputFn.mock.calls[0][0]).toEqual({
      AWS_ACCESS_KEY_ID: 'AKIA999',
      AWS_SECRET_ACCESS_KEY: 'secret999',
    });
  });
});
