#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { ZapZapStack } from '../lib/zapzap-stack';

const app = new cdk.App();
new ZapZapStack(app, 'ZapZapStack');
