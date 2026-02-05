import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { Construct } from 'constructs';

export class ZapZapStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // 1. The Bucket (Where the files live)
    const siteBucket = new s3.Bucket(this, 'ZapZapBucket', {
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Easy cleanup for demos
      autoDeleteObjects: true,
    });

    // 2. The Header Policy
    // Standard security headers go in securityHeadersBehavior;
    // COOP/COEP are "custom" as far as CloudFront is concerned.
    const engineSecurityHeaders = new cloudfront.ResponseHeadersPolicy(this, 'EngineHeaders', {
      securityHeadersBehavior: {
        contentTypeOptions: { override: true },
        frameOptions: {
          frameOption: cloudfront.HeadersFrameOption.DENY,
          override: true,
        },
        strictTransportSecurity: {
          accessControlMaxAge: cdk.Duration.days(365),
          includeSubdomains: true,
          override: true,
        },
      },
      customHeadersBehavior: {
        customHeaders: [
          { header: 'Cross-Origin-Opener-Policy', value: 'same-origin', override: true },
          { header: 'Cross-Origin-Embedder-Policy', value: 'require-corp', override: true },
        ],
      },
    });

    // 3. The CDN (Global Distribution)
    const distribution = new cloudfront.Distribution(this, 'ZapZapDist', {
      defaultBehavior: {
        origin: origins.S3BucketOrigin.withOriginAccessControl(siteBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        responseHeadersPolicy: engineSecurityHeaders,
        compress: true, // Auto-gzip/brotli
      },
      defaultRootObject: 'index.html',
    });

    // 4. The Deployment (Uploads your local 'dist' folder)
    new s3deploy.BucketDeployment(this, 'DeployWithAssets', {
      sources: [s3deploy.Source.asset('../dist')],
      destinationBucket: siteBucket,
      distribution,
      distributionPaths: ['/*'],
    });

    // 5. Output the URL
    new cdk.CfnOutput(this, 'SiteURL', {
      value: `https://${distribution.distributionDomainName}`,
    });
  }
}
