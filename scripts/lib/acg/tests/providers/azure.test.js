const os = require('os');
const path = require('path');
const mockScreenshotPath = path.join(
  os.homedir(),
  '.local',
  'share',
  'k3d-manager',
  'screenshots',
  'k3dm-azure-123.png',
);

jest.mock('../../playwright/lib/sandbox', () => ({
  _findScopedButton: jest.fn(),
  _capturePageDebugState: jest.fn().mockResolvedValue({
    screenshotPath: mockScreenshotPath,
    currentUrl: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
    visibleText: 'Azure portal snapshot',
  }),
}));

const { extractCredentials } = require('../../playwright/providers/azure');
const { _findScopedButton, _capturePageDebugState } = require('../../playwright/lib/sandbox');

function makeMockPage(scanResults) {
  const scans = Array.isArray(scanResults) ? scanResults.slice() : [scanResults];
  return {
    evaluate: jest.fn(async () => scans.length > 1 ? scans.shift() : scans[0]),
    waitForTimeout: jest.fn().mockResolvedValue(undefined),
    url: jest.fn().mockReturnValue('https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview'),
  };
}

describe('azure provider extraction', () => {
  let outputFn;

  beforeEach(() => {
    outputFn = jest.fn();
    jest.clearAllMocks();
    _findScopedButton.mockReset();
    _capturePageDebugState.mockResolvedValue({
      screenshotPath: mockScreenshotPath,
      currentUrl: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
      visibleText: 'Azure portal snapshot',
    });
  });

  test('extracts portal username/password plus subscription, tenant, resource group, and snapshot metadata', async () => {
    const page = makeMockPage({
      azureInputs: [
        { fieldLabel: 'username', fullValue: 'cloud_user_p_8f8bfbb1@realhandsonlabs.com' },
        { fieldLabel: 'password', fullValue: 'VerySecretTAP' },
      ],
      allInputs: [
        { fieldLabel: 'username', fullValue: 'cloud_user_p_8f8bfbb1@realhandsonlabs.com' },
        { fieldLabel: 'password', fullValue: 'VerySecretTAP' },
        { fieldLabel: 'subscription', fullValue: '9734ed68-621d-47ed-babd-269110dbacb1' },
        { fieldLabel: 'tenant', fullValue: '84f1e4ea-8554-43e1-8709-f0b8589ea118' },
      ],
      bodyText: 'Home\n1-5dfde6f5-playground-sandbox\nResource group\nSubscription ID\n9734ed68-621d-47ed-babd-269110dbacb1',
      currentUrl: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
    });

    await extractCredentials(page, outputFn);

    expect(outputFn).toHaveBeenCalledTimes(1);
    expect(outputFn).toHaveBeenCalledWith({
      AZURE_USERNAME: 'cloud_user_p_8f8bfbb1@realhandsonlabs.com',
      AZURE_PASSWORD: 'VerySecretTAP',
      AZURE_SUBSCRIPTION_ID: '9734ed68-621d-47ed-babd-269110dbacb1',
      AZURE_TENANT_ID: '84f1e4ea-8554-43e1-8709-f0b8589ea118',
      AZURE_RESOURCE_GROUP: '1-5dfde6f5-playground-sandbox',
      AZURE_SCREENSHOT_PATH: mockScreenshotPath,
      AZURE_PORTAL_URL: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
    });
    expect(_capturePageDebugState).toHaveBeenCalledTimes(1);
  });

  test('reopens the Azure panel once when inputs are initially absent', async () => {
    const openBtn = { click: jest.fn().mockResolvedValue(undefined) };
    _findScopedButton.mockResolvedValueOnce(openBtn).mockResolvedValue(null);
    const page = makeMockPage([
      {
        azureInputs: [],
        allInputs: [],
        bodyText: 'Azure panel closed',
        currentUrl: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
      },
      {
        azureInputs: [
          { fieldLabel: 'username', fullValue: 'cloud_user_p_8f8bfbb1@realhandsonlabs.com' },
          { fieldLabel: 'password', fullValue: 'VerySecretTAP' },
        ],
        allInputs: [
          { fieldLabel: 'username', fullValue: 'cloud_user_p_8f8bfbb1@realhandsonlabs.com' },
          { fieldLabel: 'password', fullValue: 'VerySecretTAP' },
          { fieldLabel: 'subscription', fullValue: '9734ed68-621d-47ed-babd-269110dbacb1' },
          { fieldLabel: 'tenant', fullValue: '84f1e4ea-8554-43e1-8709-f0b8589ea118' },
        ],
        bodyText: 'Home\n1-5dfde6f5-playground-sandbox\nResource group\nSubscription ID\n9734ed68-621d-47ed-babd-269110dbacb1',
        currentUrl: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
      },
    ]);

    await extractCredentials(page, outputFn);

    expect(openBtn.click).toHaveBeenCalledWith({ force: true });
    expect(outputFn).toHaveBeenCalledTimes(1);
    expect(outputFn.mock.calls[0][0].AZURE_USERNAME).toBe('cloud_user_p_8f8bfbb1@realhandsonlabs.com');
  });

  test('missing Azure credentials throws after capturing a debug snapshot', async () => {
    const page = makeMockPage({
      azureInputs: [],
      allInputs: [],
      bodyText: 'No Azure inputs',
      currentUrl: 'https://portal.azure.com/#@realhandsonlabs.com/resource/subscriptions/9734ed68-621d-47ed-babd-269110dbacb1/resourceGroups/1-5dfde6f5-playground-sandbox/overview',
    });

    await expect(extractCredentials(page, outputFn)).rejects.toThrow(
      'No credentials found in Azure provider card'
    );
    expect(_capturePageDebugState).toHaveBeenCalled();
    expect(outputFn).not.toHaveBeenCalled();
  });
});
